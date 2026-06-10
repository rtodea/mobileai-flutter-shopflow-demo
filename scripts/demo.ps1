<#
.SYNOPSIS
    Mirror the phone (scrcpy) and deploy ShopFlow over WiFi.

.DESCRIPTION
    One-shot wireless-demo helper:
      1. Auto-discovers the phone via adb mDNS (survives the Wireless-Debugging
         port changing after a reboot) and connects. Falls back to -DeviceIp.
      2. Drops any duplicate mDNS/TLS transport so commands aren't ambiguous.
      3. Launches scrcpy for screen mirroring (unless -NoMirror).
      4. Runs / installs the app with the repo's .env dart-defines.

    Requires Wireless debugging ON (Settings -> Developer options) and the phone
    on the same WiFi. Pairing persists across reboots; only the port rotates,
    which mDNS discovery handles for you.

.PARAMETER DeviceIp
    Optional explicit "<ip>:<port>" fallback if mDNS discovery comes up empty.

.PARAMETER Mode
    'run' (default, hot reload) or 'install' (build apk + install, then exit).

.PARAMETER Release   Build in release mode.
.PARAMETER NoMirror  Skip scrcpy; deploy only.

.EXAMPLE
    ./scripts/demo.ps1                       # auto-find phone, mirror + run
    ./scripts/demo.ps1 -Release              # release build
    ./scripts/demo.ps1 -Mode install -Release -NoMirror
    ./scripts/demo.ps1 -DeviceIp 10.190.11.80:40739   # explicit fallback
#>
[CmdletBinding()]
param(
    [string]$DeviceIp,
    [ValidateSet('run','install')][string]$Mode = 'run',
    [switch]$Release,
    [switch]$NoMirror
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_common.ps1"

$adb    = Get-Adb
$device = Connect-Phone -Adb $adb -DeviceIp $DeviceIp
Remove-DuplicateTransports -Adb $adb
& $adb -s $device wait-for-device
Write-Host "Device ready: $device" -ForegroundColor Green

if (-not $NoMirror) {
    $scrcpy = (Get-Command scrcpy -ErrorAction SilentlyContinue).Source
    if ($scrcpy) {
        Write-Host "Launching scrcpy (mirror) ..." -ForegroundColor Cyan
        # Note: array -ArgumentList is space-joined WITHOUT quoting in Windows
        # PowerShell, so keep each token space-free (no "ShopFlow demo").
        Start-Process $scrcpy -ArgumentList @(
            "-s", $device, "--show-touches", "--stay-awake",
            "--window-title", "ShopFlow-demo"
        )
    } else {
        Write-Warning "scrcpy not on PATH; skipping mirror. (winget install Genymobile.scrcpy)"
    }
}

Invoke-FlutterDeploy -Device $device -Mode $Mode -Release:$Release
