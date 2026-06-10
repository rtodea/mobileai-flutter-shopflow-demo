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

# Wait for full boot (boot_completed). While the emulator is still coming up,
# adb can emit transient stderr ("error: closed", "device offline"). Do NOT
# redirect adb's stderr (2>$null/2>&1) here: under ErrorActionPreference='Stop'
# that wraps the line as a terminating NativeCommandError and kills the script.
# Instead tolerate hiccups and bail clearly only if the emulator truly vanishes.
Write-Host "Waiting for '$device' to finish booting ..." -ForegroundColor DarkGray
$deadline = (Get-Date).AddSeconds(180)
$booted = $false
while ((Get-Date) -lt $deadline) {
    if (-not ((& $adb devices) -match [regex]::Escape($device))) {
        throw "Emulator '$device' disappeared while booting (it likely crashed). Re-run the script."
    }
    $prop = ''
    try { $prop = (& $adb -s $device shell getprop sys.boot_completed | Out-String).Trim() } catch { $prop = '' }
    if ($prop -eq '1') { $booted = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $booted) { throw "Emulator '$device' did not finish booting within 180s." }
Write-Host "Emulator ready: $device" -ForegroundColor Green

Invoke-FlutterDeploy -Device $device -Mode $Mode -Release:$Release
