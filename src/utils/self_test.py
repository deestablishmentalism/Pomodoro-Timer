"""Startup self-test for packaged builds: ``pomodoro-timer --self-test``.

Imports every module the app needs (exactly as the frozen app would) and checks the
bundled data files, then exits with code 0 (OK) or 1 (failure) without opening a window.
Used by CI to catch modules/data that PyInstaller left out of the bundle - something a
plain ``python -c "import ..."`` on the build machine cannot detect.

Deliberately imports nothing heavy at module level so it can run before main.py's imports.
"""
import importlib
import os
import sys
import traceback

# Modules imported (directly or indirectly) at runtime. Platform-specific ones are added below.
MODULES = [
    "tkinter",
    "customtkinter",
    "darkdetect",
    "psutil",
    "PIL.Image",
    "PIL.ImageTk",
    "pyautogui",
    "platformdirs",
    "sqlite3",
    "database.db_handler",
    "media_controls.spotify_handler",
    "media_controls.rest_media_handler",
    "ui.timer_view",
    "utils.paths",
]
if sys.platform == "win32":
    # pygetwindow -> pyrect -> doctest -> unittest (the chain that once broke the Windows build)
    MODULES += ["pygetwindow", "pyrect", "doctest", "unittest", "ctypes.wintypes"]
else:
    MODULES += ["Xlib.display"]

DATA_FILES = [
    "assets/timer-logo.png",
    "assets/timer-logo.ico",
]


def _log_path() -> str:
    # Windowed Windows builds have no console (sys.stdout is None), so also write a log file.
    # Kept out of the app folder so it can never end up inside a packaged ZIP/tarball.
    import tempfile
    return os.environ.get("POMODORO_SELF_TEST_LOG") or os.path.join(
        tempfile.gettempdir(), "pomodoro-timer-self-test.log")


def run() -> int:
    lines = []
    failed = False

    for name in MODULES:
        try:
            importlib.import_module(name)
            lines.append(f"ok    import {name}")
        except Exception:
            failed = True
            lines.append(f"FAIL  import {name}\n{traceback.format_exc()}")

    try:
        from utils.paths import get_resource_path
        for rel in DATA_FILES:
            path = get_resource_path(rel)
            ok = os.path.isfile(path)
            failed |= not ok
            lines.append(f"{'ok  ' if ok else 'FAIL'}  file   {rel} -> {path}")
    except Exception:
        failed = True
        lines.append(f"FAIL  data file check\n{traceback.format_exc()}")

    # CustomTkinter loads its theme JSON from disk at startup
    try:
        import customtkinter
        theme = os.path.join(os.path.dirname(customtkinter.__file__), "assets", "themes", "blue.json")
        ok = os.path.isfile(theme)
        failed |= not ok
        lines.append(f"{'ok  ' if ok else 'FAIL'}  file   customtkinter theme -> {theme}")
    except Exception:
        failed = True
        lines.append(f"FAIL  customtkinter theme check\n{traceback.format_exc()}")

    # Mock test: database creation and insertion in an isolated temp directory
    try:
        import contextlib
        import sqlite3
        import tempfile
        from pathlib import Path
        from unittest.mock import patch
        from database.db_handler import Db_Handler

        with tempfile.TemporaryDirectory() as tmpdir:
            mock_dir = Path(tmpdir) / "pomodoro_self_test_db"
            with patch("database.db_handler.user_data_dir", return_value=str(mock_dir)):
                db = Db_Handler()
                db.insert_timer_history(25, 5, 4, "/mock/media")
                db_file = mock_dir / "app.db"
                ok = db_file.is_file()
                with contextlib.closing(sqlite3.connect(db_file)) as conn:
                    row = conn.execute(
                        "SELECT work_duration, rest_duration, cycles, rest_media_directory FROM timer_history"
                    ).fetchone()
                ok = ok and row == (25, 5, 4, "/mock/media")
        failed |= not ok
        lines.append(f"{'ok  ' if ok else 'FAIL'}  db     database creation and insertion")
    except Exception:
        failed = True
        lines.append(f"FAIL  database creation and insertion\n{traceback.format_exc()}")

    lines.append("SELF-TEST FAILED" if failed else "SELF-TEST PASSED")
    report = "\n".join(lines)

    if sys.stdout is not None:
        print(report)
    try:
        with open(_log_path(), "w", encoding="utf-8") as f:
            f.write(report + "\n")
    except OSError:
        pass
    return 1 if failed else 0
