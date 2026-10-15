<#
.SYNOPSIS
    Pomodoro Timer - build the standalone Windows packages (no Python needed on target machines).

.DESCRIPTION
    Produces in dist\:
      pomodoro-timer\                          PyInstaller onedir build (pomodoro-timer.exe)
      pomodoro-timer-windows-x64.zip           portable build + offline install.bat / uninstall.bat
      PomodoroTimer-Setup-<version>.exe        Inno Setup installer (if Inno Setup 6 is installed)

.PARAMETER Python
    Python interpreter with requirements-dev.txt installed
    (default: .venv\Scripts\python.exe if present, else 'py -3' / 'python').

.PARAMETER Version
    Version stamped into the installer (default 1.0.0).

.PARAMETER SkipPyInstaller
    Reuse an existing dist\pomodoro-timer\.

.PARAMETER NoInstaller
    Skip the Inno Setup step.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File packaging\windows\build_windows.ps1 -Version 1.0.0
#>
param(
    [string]$Python = '',
    [string]$Version = '1.0.0',
    [switch]$SkipPyInstaller,
    [switch]$NoInstaller
)

$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Dist = Join-Path $Root 'dist'
$Build = Join-Path $Root 'build'
$OneDir = Join-Path $Dist 'pomodoro-timer'

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Invoke-Checked {
    param([string]$Exe, [string[]]$Arguments, [string]$What)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Exe @Arguments } finally { $ErrorActionPreference = $old }
    if ($LASTEXITCODE -ne 0) { throw "$What failed (exit code $LASTEXITCODE)." }
}

Push-Location $Root
try {
    # ---------- 1. PyInstaller onedir build ----------
    if (-not $SkipPyInstaller) {
        $pyArgs = @()
        if (-not $Python) {
            $venvPy = Join-Path $Root '.venv\Scripts\python.exe'
            if (Test-Path $venvPy) { $Python = $venvPy }
            elseif (Get-Command py -ErrorAction SilentlyContinue) { $Python = 'py'; $pyArgs = @('-3') }
            else { $Python = 'python' }
        }
        Write-Step "Building with PyInstaller ($Python $pyArgs)"
        Invoke-Checked $Python ($pyArgs + @('-m', 'PyInstaller', '--noconfirm', '--clean',
            '--distpath', $Dist, '--workpath', $Build, 'pomodoro-timer.spec')) 'PyInstaller build'
    }
    if (-not (Test-Path (Join-Path $OneDir 'pomodoro-timer.exe'))) {
        throw "dist\pomodoro-timer\pomodoro-timer.exe not found."
    }

    # ---------- 2. Portable ZIP (exe folder + offline installer) ----------
    $Pkg = 'pomodoro-timer-windows-x64'
    $Stage = Join-Path $Build $Pkg
    Write-Step "Creating $Pkg.zip"
    if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
    New-Item -ItemType Directory -Force -Path $Stage | Out-Null
    Copy-Item -Recurse -Path $OneDir -Destination (Join-Path $Stage 'pomodoro-timer')
    foreach ($f in 'install.bat', 'install.ps1', 'uninstall.bat', 'uninstall.ps1') {
        Copy-Item (Join-Path $Root "installer\windows\$f") $Stage
    }
    @(
        'Pomodoro Timer - portable Windows build (no Python required)',
        '',
        'Run without installing:   pomodoro-timer\pomodoro-timer.exe',
        'Install for this user:    double-click install.bat  (Start Menu/Desktop shortcuts)',
        'Uninstall:                Settings > Apps > Pomodoro Timer, or uninstall.bat',
        '',
        'Optional: VLC, mpv or ffmpeg for rest-interval media.'
    ) | Set-Content -Encoding UTF8 (Join-Path $Stage 'README.txt')
    $Zip = Join-Path $Dist "$Pkg.zip"
    if (Test-Path $Zip) { Remove-Item -Force $Zip }
    Compress-Archive -Path $Stage -DestinationPath $Zip

    # ---------- 3. Inno Setup installer ----------
    if (-not $NoInstaller) {
        $iscc = (Get-Command iscc -ErrorAction SilentlyContinue).Source
        if (-not $iscc) {
            $iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
                      "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe") |
                Where-Object { Test-Path $_ } | Select-Object -First 1
        }
        if ($iscc) {
            Write-Step "Compiling installer with $iscc"
            Invoke-Checked $iscc @("/DMyAppVersion=$Version", (Join-Path $PSScriptRoot 'setup.iss')) 'Inno Setup compile'
        } else {
            Write-Host 'Inno Setup 6 not found - skipping installer (winget install JRSoftware.InnoSetup).' -ForegroundColor Yellow
        }
    }

    Write-Step "Done. Artifacts in $Dist"
    Get-ChildItem $Dist | Format-Table Name, Length -AutoSize
}
finally {
    Pop-Location
}

