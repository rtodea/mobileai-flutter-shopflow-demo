<#
    Shared helpers for the demo/emulator deploy scripts.
    Dot-source this:  . "$PSScriptRoot\_common.ps1"
#>

$script:RepoRoot = Split-Path -Parent $PSScriptRoot

function Get-Adb {
    # Prefer adb on PATH, fall back to the Android SDK location.
    $adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
    if (-not $adb) { $adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" }
    if (-not (Test-Path $adb)) { throw "adb not found. Install Android platform-tools." }
    return $adb
}

function Find-PhoneEndpoint {
    # Ask adb's mDNS discovery for the phone's current Wireless-Debugging endpoint.
    # Returns "<ip>:<port>" of the first _adb-tls-connect._tcp service, or $null.
    param([Parameter(Mandatory)][string]$Adb)
    foreach ($line in (& $Adb mdns services 2>$null)) {
        if ($line -match '_adb-tls-connect\._tcp\s+(\d{1,3}(?:\.\d{1,3}){3}:\d+)') {
            return $Matches[1]
        }
    }
    return $null
}

function Remove-DuplicateTransports {
    # Drop mDNS/TLS transports so flutter/scrcpy aren't ambiguous when the same
    # phone is reachable via both a plain IP connection and the TLS channel.
    param([Parameter(Mandatory)][string]$Adb)
    foreach ($line in (& $Adb devices)) {
        if ($line -match '^(adb-\S+_adb-tls-connect\._tcp)\s') {
            & $Adb disconnect $Matches[1] | Out-Null
        }
    }
}

function Connect-Phone {
    <#
        Connect adb to the phone over WiFi. Tries mDNS auto-discovery first
        (survives the port changing after a reboot), then falls back to an
        explicit endpoint. Returns the connected "<ip>:<port>".
    #>
    param(
        [Parameter(Mandatory)][string]$Adb,
        [string]$DeviceIp,           # optional explicit fallback "<ip>:<port>"
        [int]$TimeoutSec = 25
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    $target   = $null

    while ((Get-Date) -lt $deadline) {
        # 1) already have a live device?
        $live = (& $Adb devices) | Where-Object { $_ -match '^(\S+)\s+device\b' } |
                ForEach-Object { ($_ -split '\s+')[0] } | Select-Object -First 1
        if ($live) { return $live }

        # 2) try mDNS discovery
        $found = Find-PhoneEndpoint -Adb $Adb
        if ($found) { $target = $found }
        elseif ($DeviceIp) { $target = $DeviceIp }

        if ($target) {
            Write-Host "Connecting adb to $target ..." -ForegroundColor Cyan
            & $Adb connect $target | Out-Host
            Start-Sleep -Milliseconds 800
            $state = (& $Adb -s $target get-state 2>$null)
            if ($state -eq 'device') { return $target }
        }

        Write-Host "Waiting for phone (mDNS/Wireless debugging)... " -ForegroundColor DarkGray
        Start-Sleep -Seconds 2
    }

    throw "Could not connect to the phone within $TimeoutSec s. Is Wireless debugging ON and the phone on the same WiFi?"
}

function Invoke-FlutterDeploy {
    <#
        Deploy the app to a device id.
          -Mode run     : flutter run (hot reload, stays attached)
          -Mode install : flutter build apk (+defines) then flutter install
        --dart-define-from-file=.env is applied when .env is present (run/build only).
    #>
    param(
        [Parameter(Mandatory)][string]$Device,
        [ValidateSet('run','install')][string]$Mode = 'run',
        [switch]$Release
    )

    Push-Location $script:RepoRoot
    try {
        $hasEnv  = Test-Path (Join-Path $script:RepoRoot '.env')
        $defines = if ($hasEnv) { @('--dart-define-from-file=.env') } else { @() }
        # Be explicit: `build apk` defaults to release, `run` defaults to debug.
        # Pin the flavor so -Release means the same thing across both modes.
        $flavor  = if ($Release) { '--release' } else { '--debug' }

        if ($Mode -eq 'install') {
            $buildArgs = @('build','apk',$flavor) + $defines
            Write-Host "flutter $($buildArgs -join ' ')" -ForegroundColor Cyan
            & flutter @buildArgs
            if ($LASTEXITCODE -ne 0) { throw "flutter build failed ($LASTEXITCODE)" }

            $installArgs = @('install','-d',$Device,$flavor)
            Write-Host "flutter $($installArgs -join ' ')" -ForegroundColor Cyan
            & flutter @installArgs
        } else {
            $runArgs = @('run','-d',$Device,$flavor) + $defines
            Write-Host "flutter $($runArgs -join ' ')" -ForegroundColor Cyan
            & flutter @runArgs
        }
    } finally {
        Pop-Location
    }
}
