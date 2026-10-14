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

## Requirements

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

## Installation

Both installers install for the current user only and need **no admin rights** for the app itself. Each one creates a private Python virtual environment, so your system Python is not touched. Running an installer again updates an existing install.

### Linux
```bash
git clone https://github.com/deestablishmentalism/Pomodoro-Timer.git pomodoro-timer
cd pomodoro-timer
chmod +x installer/linux/*.sh
./installer/linux/install.sh            # add --yes to accept all prompts
```
This installs:
- `~/.local/share/pomodoro-timer/`: the app and its virtual environment
- `~/.local/bin/pomodoro-timer`: the launcher command
- A **Pomodoro Timer** entry in your application menu

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

## Project structure
```
pomodoro-timer/
├── src/
│   ├── main.py                       # App window, timer setup form, rest-media picker
│   ├── ui/timer_view.py              # Running-timer UI and focus/rest state machine
│   └── media_controls/
│       ├── spotify_handler.py        # State-aware Spotify pause/resume
│       └── rest_media_handler.py     # Random, no-repeat rest-interval media playback
├── installer/
│   ├── linux/   install.sh, uninstall.sh
│   └── windows/ install.bat, install.ps1, uninstall.bat, uninstall.ps1
├── requirements.txt
└── run.sh                            # Quick run from source (Linux)
```

