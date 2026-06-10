<#
.SYNOPSIS
    Launch an Android emulator and deploy ShopFlow to it.

.DESCRIPTION
    1. Reuses a running emulator if there is one; otherwise launches the named AVD.
    2. Waits for the emulator to finish booting.
    3. Runs / installs the app with the repo's .env dart-defines.

    List available AVDs with:  flutter emulators
    Create one with:           flutter emulators --create --name xyz

.PARAMETER Name
    AVD id to launch (default: ShopFlowPixel). Ignored if an emulator is already running.

.PARAMETER Mode
    'run' (default, hot reload) or 'install' (build apk + install, then exit).

.PARAMETER Release   Build in release mode.
.PARAMETER Fresh     Cold-boot / wipe-free fresh start (passes -no-snapshot-load).
.PARAMETER NoLaunch  Don't launch; assume an emulator is already running.

.EXAMPLE
    ./scripts/emulator.ps1                      # launch ShopFlowPixel, run
    ./scripts/emulator.ps1 -Name ZeamFireTV
    ./scripts/emulator.ps1 -Mode install -Release
#>
[CmdletBinding()]
param(
    [string]$Name = 'ShopFlowPixel',
    [ValidateSet('run','install')][string]$Mode = 'run',
    [switch]$Release,
    [switch]$Fresh,
    [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_common.ps1"

$adb = Get-Adb

function Get-RunningEmulator {
    param([Parameter(Mandatory)][string]$Adb)
    foreach ($line in (& $Adb devices)) {
        if ($line -match '^(emulator-\d+)\s+device\b') { return $Matches[1] }
    }
    return $null
}

$device = Get-RunningEmulator -Adb $adb

if (-not $device -and -not $NoLaunch) {
    Write-Host "Launching emulator '$Name' ..." -ForegroundColor Cyan
    # Launch via the SDK emulator directly so we can pass cold-boot flags.
    $emu = "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe"
    if (Test-Path $emu) {
        $emuArgs = @('-avd', $Name)
        if ($Fresh) { $emuArgs += '-no-snapshot-load' }
        Start-Process $emu -ArgumentList $emuArgs
    } else {
        # Fallback to flutter's launcher (no cold-boot control).
        & flutter emulators --launch $Name | Out-Host
    }

    Write-Host "Waiting for emulator to appear ..." -ForegroundColor DarkGray
    $deadline = (Get-Date).AddSeconds(120)
    while (-not $device -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $device = Get-RunningEmulator -Adb $adb
    }
    if (-not $device) { throw "Emulator '$Name' did not come up within 120s." }
}

if (-not $device) { throw "No running emulator and -NoLaunch was set." }

# Wait for full boot (package manager + boot_completed).
Write-Host "Waiting for '$device' to finish booting ..." -ForegroundColor DarkGray
& $adb -s $device wait-for-device
$deadline = (Get-Date).AddSeconds(120)
while ((Get-Date) -lt $deadline) {
    $booted = (& $adb -s $device shell getprop sys.boot_completed 2>$null).Trim()
    if ($booted -eq '1') { break }
    Start-Sleep -Seconds 2
}
Write-Host "Emulator ready: $device" -ForegroundColor Green

Invoke-FlutterDeploy -Device $device -Mode $Mode -Release:$Release
