# -*- mode: python ; coding: utf-8 -*-
# PyInstaller spec for Pomodoro Timer (Linux + Windows, onedir build).
#
#   pip install -r requirements-dev.txt
#   pyinstaller --noconfirm --clean pomodoro-timer.spec
#
# Output: dist/pomodoro-timer/  (pomodoro-timer[.exe] + _internal/)
# onedir is used instead of onefile: much faster start-up (no unpacking to a temp dir
# on every launch) and AppImage / Inno Setup take a directory as input anyway.
import os
import sys

from PyInstaller.utils.hooks import collect_data_files

IS_WINDOWS = sys.platform == "win32"
ROOT = os.path.abspath(SPECPATH)

# CustomTkinter ships JSON themes and fonts that are loaded from disk at runtime
datas = collect_data_files("customtkinter")
datas += [(os.path.join(ROOT, "assets"), "assets")]

hiddenimports = [
    "customtkinter",
    "darkdetect",
    "psutil",
    "pyautogui",
    "PIL._tkinter_finder",
    # Local packages (media_controls is a namespace package - list them explicitly)
    "media_controls.spotify_handler",
    "media_controls.rest_media_handler",
    "ui.timer_view",
    "utils.paths",
]
if IS_WINDOWS:
    hiddenimports += ["pygetwindow", "ctypes.wintypes"]
else:
    hiddenimports += ["Xlib", "Xlib.display"]  # pyautogui's X11 backend

a = Analysis(
    [os.path.join(ROOT, "src", "main.py")],
    pathex=[os.path.join(ROOT, "src")],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=["test", "unittest", "pydoc_data", "PyInstaller"],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name="pomodoro-timer",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,          # UPX frequently corrupts Tcl/Tk and triggers antivirus false positives
    console=False,      # windowed GUI app: no terminal window on Windows
    icon=os.path.join(ROOT, "assets", "timer-logo.ico") if IS_WINDOWS else None,
)

coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name="pomodoro-timer",
)

