<#
.SYNOPSIS
    Pomodoro Timer - Windows installer (per-user, no admin rights needed).

.DESCRIPTION
    Installs to %LOCALAPPDATA%\PomodoroTimer (app code + private virtualenv),
    creates Start Menu / Desktop shortcuts and registers an entry in
    "Settings > Apps" so it can be uninstalled from there.

.PARAMETER NoDesktopShortcut
    Skip creating the Desktop shortcut.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install.ps1
#>
param(
    [switch]$NoDesktopShortcut
)

$ErrorActionPreference = 'Stop'

$AppName     = 'Pomodoro Timer'
$AppId       = 'PomodoroTimer'
$AppVersion  = '1.0.0'
$MinPyMinor  = 8                     # Python 3.8+
$InstallDir  = Join-Path $env:LOCALAPPDATA $AppId
$RepoRoot    = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$StartMenuLnk = Join-Path ([Environment]::GetFolderPath('Programs')) "$AppName.lnk"
$DesktopLnk   = Join-Path ([Environment]::GetFolderPath('Desktop')) "$AppName.lnk"
$UninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$AppId"

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

# Run a native command; fail on non-zero exit code. (Native stderr output such as
# pip warnings must not be turned into terminating errors, hence 'Continue'.)
function Invoke-Checked {
    param([string]$Exe, [string[]]$Arguments, [string]$What)
    $old = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Exe @Arguments } finally { $ErrorActionPreference = $old }
    if ($LASTEXITCODE -ne 0) { throw "$What failed (exit code $LASTEXITCODE)." }
}

# Find a real Python 3.8+ (skips the Microsoft Store "python.exe" stub).
function Find-Python {
    $candidates = @(
        @{ Exe = 'py';      Args = @('-3') },
        @{ Exe = 'python';  Args = @() },
        @{ Exe = 'python3'; Args = @() }
    )
    foreach ($c in $candidates) {
        if (-not (Get-Command $c.Exe -ErrorAction SilentlyContinue)) { continue }
        $old = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $ver = & $c.Exe @($c.Args) -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
        } catch { $ver = $null } finally { $ErrorActionPreference = $old }
        if ($LASTEXITCODE -ne 0 -or -not $ver) { continue }
        $parts = "$ver".Trim().Split('.')
        if ([int]$parts[0] -eq 3 -and [int]$parts[1] -ge $MinPyMinor) {
            $c.Version = "$ver".Trim()
            return $c
        }
    }
    return $null
}

try {
    # ---------- 1. Python ----------
    Write-Step 'Checking Python...'
    $py = Find-Python
    if (-not $py) {
        throw ("Python 3.$MinPyMinor+ was not found.`n" +
               "Install it from https://www.python.org/downloads/ (tick 'Add python.exe to PATH' " +
               "and keep 'tcl/tk and IDLE' selected), then re-run this installer.")
    }
    Write-Host "    Python $($py.Version) ($($py.Exe) $($py.Args -join ' '))"

    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    & $py.Exe @($py.Args) -c 'import tkinter' 2>$null
    $ErrorActionPreference = $old
    if ($LASTEXITCODE -ne 0) {
        throw "Python is missing tkinter. Re-run the Python installer, choose 'Modify' and enable 'tcl/tk and IDLE'."
    }

    # ---------- 2. Close a running copy (files would be locked) ----------
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($InstallDir, [StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object { Write-Step "Closing running $AppName..."; Stop-Process -Id $_.Id -Force }

    # ---------- 3. Copy app ----------
    Write-Step "Installing app to $InstallDir"
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $AppDir = Join-Path $InstallDir 'app'
    if (Test-Path $AppDir) { Remove-Item -Recurse -Force $AppDir }
    Copy-Item -Recurse -Path (Join-Path $RepoRoot 'src') -Destination $AppDir
    Get-ChildItem -Path $AppDir -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force
    Copy-Item (Join-Path $RepoRoot 'requirements.txt') (Join-Path $InstallDir 'requirements.txt') -Force
    Copy-Item (Join-Path $PSScriptRoot 'uninstall.ps1') (Join-Path $InstallDir 'uninstall.ps1') -Force

    # ---------- 4. Virtualenv + Python deps ----------
    $Venv    = Join-Path $InstallDir 'venv'
    $VenvPy  = Join-Path $Venv 'Scripts\python.exe'
    $VenvPyw = Join-Path $Venv 'Scripts\pythonw.exe'
    if (-not (Test-Path $VenvPy)) {
        Write-Step 'Creating virtual environment...'
        Invoke-Checked $py.Exe (@($py.Args) + @('-m', 'venv', $Venv)) 'Creating the virtual environment'
    }
    Write-Step 'Installing Python dependencies...'
    Invoke-Checked $VenvPy @('-m', 'pip', 'install', '--upgrade', 'pip', '--quiet') 'Upgrading pip'
    Invoke-Checked $VenvPy @('-m', 'pip', 'install', '-r', (Join-Path $InstallDir 'requirements.txt'), '--quiet') 'Installing dependencies'

    # ---------- 5. Shortcuts (pythonw = no console window) ----------
    Write-Step 'Creating shortcuts...'
    $MainPy = Join-Path $AppDir 'main.py'
    $Icon = @((Join-Path $AppDir 'assets\icon.ico'), (Join-Path $AppDir 'icon.ico')) |
            Where-Object { Test-Path $_ } | Select-Object -First 1
    $shell = New-Object -ComObject WScript.Shell
    $targets = @($StartMenuLnk)
    if (-not $NoDesktopShortcut) { $targets += $DesktopLnk }
    foreach ($lnkPath in $targets) {
        $lnk = $shell.CreateShortcut($lnkPath)
        $lnk.TargetPath       = $VenvPyw
        $lnk.Arguments        = "`"$MainPy`""
        $lnk.WorkingDirectory = $AppDir
        $lnk.Description      = $AppName
        if ($Icon) { $lnk.IconLocation = $Icon }
        $lnk.Save()
    }

    # ---------- 6. Register in Settings > Apps ----------
    Write-Step 'Registering uninstaller...'
    $UninstallCmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$InstallDir\uninstall.ps1`""
    New-Item -Path $UninstallKey -Force | Out-Null
    $props = @{
        DisplayName     = $AppName
        DisplayVersion  = $AppVersion
        Publisher       = $AppName
        InstallLocation = $InstallDir
        UninstallString = $UninstallCmd
        QuietUninstallString = "$UninstallCmd -Yes"
    }
    foreach ($k in $props.Keys) { Set-ItemProperty -Path $UninstallKey -Name $k -Value $props[$k] }
    if ($Icon) { Set-ItemProperty -Path $UninstallKey -Name 'DisplayIcon' -Value $Icon }
    New-ItemProperty -Path $UninstallKey -Name 'NoModify' -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $UninstallKey -Name 'NoRepair' -Value 1 -PropertyType DWord -Force | Out-Null

    # ---------- 7. Optional tools hint ----------
    $players = 'mpv', 'ffplay', 'vlc' | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue }
    $vlcPaths = "$env:ProgramFiles\VideoLAN\VLC\vlc.exe", "${env:ProgramFiles(x86)}\VideoLAN\VLC\vlc.exe"
    if (-not $players -and -not ($vlcPaths | Where-Object { Test-Path $_ })) {
        Write-Host ''
        Write-Host 'Note: no media player found for rest-interval media.' -ForegroundColor Yellow
        Write-Host '      Install one of: VLC (https://www.videolan.org), mpv or ffmpeg - e.g. "winget install VideoLAN.VLC".'
    }

    Write-Host ''
    Write-Host "$AppName installed." -ForegroundColor Green
    Write-Host '    Launch it from the Start Menu or Desktop shortcut.'
    Write-Host "    Uninstall via Settings > Apps, or run uninstall.bat."
    exit 0
}
catch {
    Write-Host ''
    Write-Host "Installation failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

