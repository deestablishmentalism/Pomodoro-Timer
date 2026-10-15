# Pomodoro Timer

A desktop Pomodoro timer for **Linux** and **Windows**, built with Python and [CustomTkinter](https://github.com/TomSchimansky/CustomTkinter).
Set your focus time, number of cycles and rest length. During rest intervals the app can pause your Spotify music and play your own break media, then resume Spotify when it's time to focus again.

---

## Features

### Timer
- **Configurable sessions.** Set the *cycle duration* (focus minutes), the *number of cycles* and the *rest interval* (minutes). A session runs `cycles × (focus → rest)`. Set the rest to `0` to skip rest phases.
- **Live session summary.** Shows the total session length (e.g. `4 x (25 min focus + 5 min rest) = 2h 00m total`) while you type.
- **Running timer view:**
  - Countdown (`HH:MM:SS`) and a progress bar, colour-coded per phase (green = FOCUS, blue = REST, yellow = DONE)
  - "Cycle X of Y" label and a dot for each cycle
  - Time left in the whole session
  - A sound plays when each phase ends
- **Controls:** **Pause / Resume**, **Skip** (jump to the next phase) and **Stop** (go back to the home screen).

### Spotify control during rest
- When a rest interval starts, Spotify is **paused only if it is currently playing**. If you already paused it, the app leaves it alone.
- When the rest interval ends (timer runs out, **Skip**, **Stop**, or closing the app), Spotify **resumes only if the app was the one that paused it**. If you resumed or paused it yourself during the break, the app won't touch it.
- The app never sends a blind play/pause toggle:
  - **Linux:** reads the playback state and sends explicit *Play*/*Pause* commands over D-Bus (MPRIS) via `playerctl`, `gdbus` or `dbus-send`. If none of these work, it falls back to `xdotool`.
  - **Windows:** reads the state from the Spotify window title and only presses Space when the state has to change.

### Rest media
- Click **Select Rest Media** and choose a folder. All audio/video files in it (subfolders included) are played during rest intervals and stopped when the rest ends.
- Supported formats: `mp3 wav flac ogg oga opus m4a aac wma mp4 mkv webm avi mov wmv flv m4v mpg mpeg`
- Files play in **random order without repeats**. Every file plays once before any repeats, and a new round never starts with the file that just played.
- A folder with a **single file** loops that file for the whole break.
- Playback uses an external player: **mpv**, **ffplay** (ffmpeg) or **VLC**, whichever is installed.

---

## Pre-built Downloads (No Python Required)

Grab the latest build from the [Releases page](https://github.com/deestablishmentalism/Pomodoro-Timer/releases). These are self-contained: **Python, Tkinter, pip and virtual environments are NOT needed** on your machine.

| OS | File | How to use |
|---|---|---|
| **Linux** | `PomodoroTimer-x86_64.AppImage` | `chmod +x PomodoroTimer-x86_64.AppImage && ./PomodoroTimer-x86_64.AppImage`. Single file, runs on most distros, nothing to install |
| **Linux** | `pomodoro-timer-linux-x86_64.tar.gz` | Extract, then run `./install.sh` (adds an app-menu entry and the `pomodoro-timer` command), or run `./pomodoro-timer/pomodoro-timer` directly |
| **Windows** | `PomodoroTimer-Setup-<version>.exe` | Double-click the setup wizard. Installs per-user (no admin), adds Start Menu/Desktop shortcuts and an entry in **Settings > Apps** |
| **Windows** | `pomodoro-timer-windows-x64.zip` | Portable: extract and run `pomodoro-timer\pomodoro-timer.exe`, or double-click `install.bat` to add shortcuts |

The [optional tools](#optional) below (Spotify control, rest media players) still apply.

> Windows SmartScreen may warn about an unrecognised app because the builds are not code-signed. Click **More info → Run anyway**.

---

## Requirements

These are needed only to **run or install from source**. The pre-built downloads above need only the optional tools.

### Required
| | Linux | Windows |
|---|---|---|
| **Python** | 3.8 or newer (`python3`) | 3.8 or newer from [python.org](https://www.python.org/downloads/) |
| **Tkinter** | `python3-tk` (Debian/Ubuntu/openSUSE), `python3-tkinter` (Fedora), `tk` (Arch) | Included. Keep **"tcl/tk and IDLE"** ticked in the Python installer |
| **venv** | `python3-venv` (Debian/Ubuntu only; other distros ship it with Python) | Included |

Python packages (installed automatically, see [requirements.txt](requirements.txt)):
`customtkinter`, `psutil`, `pyautogui`, `pygetwindow` (Windows only).

### Optional
| Purpose | Linux | Windows |
|---|---|---|
| Spotify pause/resume | `playerctl` (recommended). `gdbus`/`dbus-send` also work. `xdotool` is the fallback on X11 | Nothing extra. Spotify desktop app must be running |
| Rest media playback | `mpv`, `ffmpeg` (ffplay) or `vlc` | VLC, mpv or ffmpeg (e.g. `winget install VideoLAN.VLC`) |

> On Linux the installer detects your package manager (apt, dnf, pacman, zypper) and offers to install any missing required and optional packages for you.

---

## Installation (from source)

> Just want to use the app? Use the [pre-built downloads](#pre-built-downloads-no-python-required) instead, no Python required.

Both installers install for the current user only and need **no admin rights** for the app itself. Running an installer again updates an existing install. They work in two modes:
- **Binary mode (no Python):** used automatically when a pre-built build is present, i.e. inside an extracted release archive, or after you [built the packages yourself](#building-the-standalone-packages) (`dist/pomodoro-timer/`). Force it with `--binary` (Linux) / `-Binary` (Windows).
- **Source mode:** creates a private Python virtual environment, so your system Python is not touched. Force it with `--source` / `-Source`.

**Before following the steps below, make sure that the repository is already downloaded--refer to the instructions below to successfully download the repository.**

### VIA Downloading the zip file

Refer to these steps for downloading the zip file.
1. Go back on the top of this repository
2. Find and then left-click on the code button
3. Click the download zip
4. Extract the file and then proceed to the instructions below

### VIA Cloning the repository

Copy the line below and then run inside the terminal.
```bash
git clone https://github.com/deestablishmentalism/Pomodoro-Timer.git pomodoro-timer
```
Then proceed to the steps below.

### Linux
**Exclude the first line if repository is already downloaded.**
```bash
git clone https://github.com/deestablishmentalism/Pomodoro-Timer.git pomodoro-timer # First line
cd pomodoro-timer
chmod +x installer/linux/*.sh
./installer/linux/install.sh            
```
This installs:
- `~/.local/share/pomodoro-timer/`: the app and its virtual environment
- `~/.local/bin/pomodoro-timer`: the launcher command
- A **Pomodoro Timer** desktop entry in your application menu

If the installer warns that `~/.local/bin` is not on your `PATH`, add this line to `~/.bashrc` (or your shell's rc file):
```bash
export PATH="$HOME/.local/bin:$PATH"
```

### Windows
Double-click **`installer\windows\install.bat`**, or run it from PowerShell:
```powershell
powershell -ExecutionPolicy Bypass -File installer\windows\install.ps1
# add -NoDesktopShortcut to skip the Desktop shortcut
```
This installs:
- `%LOCALAPPDATA%\PomodoroTimer\`: the app and its virtual environment
- **Start Menu** and **Desktop** shortcuts, which open the app without a console window
- An entry in **Settings > Apps**

---

## Running

| | Linux | Windows |
|---|---|---|
| Installed app | App menu → **Pomodoro Timer**, or run `pomodoro-timer` | Start Menu / Desktop → **Pomodoro Timer** |

### From source (without installing)
**Linux**
```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python src/main.py        # or: ./run.sh
```

**Windows (PowerShell)**
```powershell
py -3 -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python src\main.py
```

---

## Uninstalling

**Linux**
```bash
~/.local/share/pomodoro-timer/uninstall.sh      # or ./installer/linux/uninstall.sh  (add --yes to skip the prompt)
```

**Windows**
- **Settings > Apps → Pomodoro Timer → Uninstall**, or
- Double-click `installer\windows\uninstall.bat`, or
- `powershell -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\PomodoroTimer\uninstall.ps1"` (add `-Yes` to skip the prompt)

The uninstallers remove the app folder, the launcher and shortcuts, and the menu or Settings entry. System packages such as Python, `playerctl` or VLC are left installed.

---

## Building the standalone packages

Packages are built with [PyInstaller](https://pyinstaller.org) and must be built **on the target OS** (no cross-compiling). Pushing a tag like `v1.0.0` makes [GitHub Actions](.github/workflows/package.yml) build everything on Linux and Windows and publish a GitHub Release.

To build locally:

**Linux:** produces the AppImage and the portable tarball in `dist/`
```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
packaging/linux/build_linux.sh            # --no-appimage to skip the AppImage
```

**Windows:** produces the portable ZIP and, if [Inno Setup 6](https://jrsoftware.org/isinfo.php) is installed, the setup wizard in `dist\`
```powershell
py -3 -m venv .venv; .venv\Scripts\Activate.ps1
pip install -r requirements-dev.txt
powershell -ExecutionPolicy Bypass -File packaging\windows\build_windows.ps1 -Version 1.0.0
```

The icons in `assets/` (`timer-logo.ico`, `timer-logo-256.png`) are generated from `timer-logo.png` with `python packaging/make_icons.py`.

---

## Project structure
```
pomodoro-timer/
├── src/
│   ├── main.py                       # App window, timer setup form, rest-media picker
│   ├── ui/timer_view.py              # Running-timer UI and focus/rest state machine
│   ├── utils/paths.py                # Resource paths (source and PyInstaller bundle)
│   └── media_controls/
│       ├── spotify_handler.py        # State-aware Spotify pause/resume
│       └── rest_media_handler.py     # Random, no-repeat rest-interval media playback
├── assets/                           # Logo (.png, 256px .png, multi-size .ico)
├── installer/
│   ├── linux/   install.sh, uninstall.sh
│   └── windows/ install.bat, install.ps1, uninstall.bat, uninstall.ps1
├── packaging/
│   ├── make_icons.py                 # Generates the .ico / 256px icon
│   ├── linux/   build_linux.sh, build_appimage.sh
│   └── windows/ build_windows.ps1, setup.iss (Inno Setup)
├── pomodoro-timer.spec               # PyInstaller build configuration
├── .github/workflows/package.yml     # CI: builds and releases packages
├── requirements.txt
├── requirements-dev.txt              # + PyInstaller (build only)
└── run.sh                            # Quick run from source (Linux)
```
## Final Notes
This app is highly customized for the repository owner's personal use, there are a lot of flaws in the app and is untested in a production environment. **To find bugs and further improvements, FEEDBACKS ARE NEEDED.** 
