<#
.SYNOPSIS
    Pomodoro Timer - Windows uninstaller.

.DESCRIPTION
    Removes the install folder, shortcuts and the "Settings > Apps" entry
    created by install.ps1. Python itself and media players are left alone.

.PARAMETER Yes
    Do not ask for confirmation.
#>
param(
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

$AppName      = 'Pomodoro Timer'
$AppId        = 'PomodoroTimer'
$InstallDir   = Join-Path $env:LOCALAPPDATA $AppId
$StartMenuLnk = Join-Path ([Environment]::GetFolderPath('Programs')) "$AppName.lnk"
$DesktopLnk   = Join-Path ([Environment]::GetFolderPath('Desktop')) "$AppName.lnk"
$UninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$AppId"

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

$targets = @($InstallDir, $StartMenuLnk, $DesktopLnk, $UninstallKey) | Where-Object { Test-Path $_ }
if (-not $targets) {
    Write-Host "$AppName does not appear to be installed."
    exit 0
}

if (-not $Yes) {
    Write-Host 'This will remove:'
    $targets | ForEach-Object { Write-Host "    $_" }
    $reply = Read-Host 'Continue? [y/N]'
    if ($reply -notmatch '^[Yy]$') { Write-Host 'Aborted.'; exit 1 }
}

try {
    # Close the app if it is running (its files would be locked)
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($InstallDir, [StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object { Write-Step "Closing running $AppName..."; Stop-Process -Id $_.Id -Force }
    Start-Sleep -Milliseconds 500

    Write-Step 'Removing shortcuts...'
    foreach ($lnk in @($StartMenuLnk, $DesktopLnk)) {
        if (Test-Path $lnk) { Remove-Item -Force $lnk }
    }

    Write-Step 'Removing Settings > Apps entry...'
    if (Test-Path $UninstallKey) { Remove-Item -Recurse -Force $UninstallKey }

    Write-Step "Removing $InstallDir..."
    # This script may itself live in the install dir - step out of it first.
    Set-Location $env:TEMP
    if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir }

    Write-Host ''
    Write-Host "$AppName uninstalled." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ''
    Write-Host "Uninstall failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

