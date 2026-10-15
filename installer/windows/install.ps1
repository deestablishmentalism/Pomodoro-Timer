<#
.SYNOPSIS
    Pomodoro Timer - Windows installer (per-user, no admin rights needed).

.DESCRIPTION
    Installs to %LOCALAPPDATA%\PomodoroTimer, creates Start Menu / Desktop shortcuts
    and registers an entry in "Settings > Apps" so it can be uninstalled from there.

    Two modes:
      binary  Installs a pre-built standalone build - NO Python needed. Used automatically
              when .\pomodoro-timer\pomodoro-timer.exe (portable ZIP) or
              <repo>\dist\pomodoro-timer\pomodoro-timer.exe (local build) exists.
      source  Builds from source: private virtualenv + pip install (needs Python 3.8+).

    Tip: the PomodoroTimer-Setup-<version>.exe installer from the Releases page is the
    easiest option and needs no Python either.

.PARAMETER NoDesktopShortcut
    Skip creating the Desktop shortcut.

.PARAMETER Binary
    Require the pre-built binary mode.

.PARAMETER Source
    Force the build-from-source (virtualenv) mode.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File install.ps1
#>
param(
    [switch]$NoDesktopShortcut,
    [switch]$Binary,
    [switch]$Source
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
$ExeName      = 'pomodoro-timer.exe'

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

# Wrap a PNG in a single-image .ico (PNG-compressed ICO entries are supported
# since Windows Vista). Shortcuts and "Settings > Apps" can't use a .png directly.
function Convert-PngToIco {
    param([string]$PngPath, [string]$IcoPath)
    $png = [IO.File]::ReadAllBytes($PngPath)
    # Width/height are big-endian UInt32s in the IHDR chunk (offsets 16 and 20)
    $w = [int]$png[18] * 256 + [int]$png[19]
    $h = [int]$png[22] * 256 + [int]$png[23]
    $fs = [IO.File]::Create($IcoPath)
    $bw = New-Object IO.BinaryWriter($fs)
    try {
        $bw.Write([UInt16]0)                          # reserved
        $bw.Write([UInt16]1)                          # type: icon
        $bw.Write([UInt16]1)                          # image count
        $bw.Write([byte]$(if ($w -ge 256) { 0 } else { $w }))   # 0 means 256
        $bw.Write([byte]$(if ($h -ge 256) { 0 } else { $h }))
        $bw.Write([byte]0)                            # palette colours
        $bw.Write([byte]0)                            # reserved
        $bw.Write([UInt16]1)                          # colour planes
        $bw.Write([UInt16]32)                         # bits per pixel
        $bw.Write([UInt32]$png.Length)                # image data size
        $bw.Write([UInt32]22)                         # data offset (6 + 16)
        $bw.Write($png)
    } finally { $bw.Close() }
}

try {
    # ---------- 0. Install mode ----------
    if ($Binary -and $Source) { throw 'Use either -Binary or -Source, not both.' }
    # A pre-built standalone build: next to this script (portable ZIP) or in <repo>\dist (local build)
    $BinarySrc = @((Join-Path $PSScriptRoot 'pomodoro-timer'), (Join-Path $RepoRoot 'dist\pomodoro-timer')) |
        Where-Object { Test-Path (Join-Path $_ $ExeName) } | Select-Object -First 1
    if ($Binary)     { $Mode = 'binary' }
    elseif ($Source) { $Mode = 'source' }
    elseif ($BinarySrc) { $Mode = 'binary' }
    else             { $Mode = 'source' }
    if ($Mode -eq 'binary' -and -not $BinarySrc) {
        throw ("No pre-built binary found (expected .\pomodoro-timer\$ExeName).`n" +
               'Download PomodoroTimer-Setup.exe or the portable ZIP from the Releases page, or use -Source.')
    }
    if ($Mode -eq 'source' -and -not (Test-Path (Join-Path $RepoRoot 'src\main.py'))) {
        throw "Source code not found at $RepoRoot\src - use -Binary."
    }
    if ($Mode -eq 'binary') { Write-Step "Installing pre-built binary from $BinarySrc (no Python required)" }
    else                    { Write-Step 'Installing from source (Python virtualenv)' }

    if ($Mode -eq 'source') {
        # ---------- 1. Python ----------
        Write-Step 'Checking Python...'
        $py = Find-Python
        if (-not $py) {
            throw ("Python 3.$MinPyMinor+ was not found.`n" +
                   "Install it from https://www.python.org/downloads/ (tick 'Add python.exe to PATH' " +
                   "and keep 'tcl/tk and IDLE' selected), then re-run this installer.`n" +
                   'Or use the pre-built PomodoroTimer-Setup.exe from the Releases page (no Python needed).')
        }
        Write-Host "    Python $($py.Version) ($($py.Exe) $($py.Args -join ' '))"

        $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        & $py.Exe @($py.Args) -c 'import tkinter' 2>$null
        $ErrorActionPreference = $old
        if ($LASTEXITCODE -ne 0) {
            throw "Python is missing tkinter. Re-run the Python installer, choose 'Modify' and enable 'tcl/tk and IDLE'."
        }
    }

    # ---------- 2. Close a running copy (files would be locked) ----------
    Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -and $_.Path.StartsWith($InstallDir, [StringComparison]::OrdinalIgnoreCase) } |
        ForEach-Object { Write-Step "Closing running $AppName..."; Stop-Process -Id $_.Id -Force }
    Start-Sleep -Milliseconds 500

    # ---------- 3. Copy app ----------
    Write-Step "Installing app to $InstallDir"
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $AppDir    = Join-Path $InstallDir 'app'
    $BinDir    = Join-Path $InstallDir 'bin'
    $AssetsDir = Join-Path $InstallDir 'assets'
    foreach ($d in @($AppDir, $BinDir, $AssetsDir)) {
        if (Test-Path $d) { Remove-Item -Recurse -Force $d }
    }
    if ($Mode -eq 'binary') {
        Copy-Item -Recurse -Path $BinarySrc -Destination $BinDir
        # A previous source install's virtualenv is no longer needed
        foreach ($p in @((Join-Path $InstallDir 'venv'), (Join-Path $InstallDir 'requirements.txt'))) {
            if (Test-Path $p) { Remove-Item -Recurse -Force $p }
        }
        # PyInstaller 6 keeps data files in _internal\, older versions next to the exe
        $SrcAssets = @((Join-Path $BinDir '_internal\assets'), (Join-Path $BinDir 'assets'), (Join-Path $RepoRoot 'assets')) |
            Where-Object { Test-Path $_ } | Select-Object -First 1
    } else {
        Copy-Item -Recurse -Path (Join-Path $RepoRoot 'src') -Destination $AppDir
        Get-ChildItem -Path $AppDir -Recurse -Directory -Filter '__pycache__' | Remove-Item -Recurse -Force
        $SrcAssets = Join-Path $RepoRoot 'assets'
        Copy-Item (Join-Path $RepoRoot 'requirements.txt') (Join-Path $InstallDir 'requirements.txt') -Force
    }
    if ($SrcAssets -and (Test-Path $SrcAssets)) { Copy-Item -Recurse -Path $SrcAssets -Destination $AssetsDir }
    Copy-Item (Join-Path $PSScriptRoot 'uninstall.ps1') (Join-Path $InstallDir 'uninstall.ps1') -Force

    # ---------- 4. Virtualenv + Python deps (source mode only) ----------
    if ($Mode -eq 'source') {
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
    }

    # ---------- 5. Shortcuts (exe / pythonw = no console window) ----------
    Write-Step 'Creating shortcuts...'
    $Icon = $null
    $IcoPath = Join-Path $InstallDir 'timer-logo.ico'
    $BundledIco = Join-Path $AssetsDir 'timer-logo.ico'
    $Png = Join-Path $AssetsDir 'timer-logo.png'
    if (Test-Path $BundledIco) {
        Copy-Item $BundledIco $IcoPath -Force            # multi-resolution icon
        $Icon = $IcoPath
    } elseif (Test-Path $Png) {
        Convert-PngToIco $Png $IcoPath
        $Icon = $IcoPath
    }
    if ($Mode -eq 'binary') {
        $Target = Join-Path $BinDir $ExeName
        $TargetArgs = ''
        $WorkDir = $BinDir
        if (-not $Icon) { $Icon = $Target }              # icon embedded in the exe
    } else {
        $Target = $VenvPyw
        $TargetArgs = "`"$(Join-Path $AppDir 'main.py')`""
        $WorkDir = $AppDir
    }
    $shell = New-Object -ComObject WScript.Shell
    $targets = @($StartMenuLnk)
    if (-not $NoDesktopShortcut) { $targets += $DesktopLnk }
    foreach ($lnkPath in $targets) {
        if (Test-Path $lnkPath) { Remove-Item -Force $lnkPath }   # avoid stale cached icon
        $lnk = $shell.CreateShortcut($lnkPath)
        $lnk.TargetPath       = $Target
        $lnk.Arguments        = $TargetArgs
        $lnk.WorkingDirectory = $WorkDir
        $lnk.Description      = $AppName
        if ($Icon) { $lnk.IconLocation = "$Icon,0" }
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

