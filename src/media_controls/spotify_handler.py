import platform
import queue
import subprocess
import threading
import time

import psutil
import pyautogui

IS_WINDOWS = platform.system() == "Windows"

if IS_WINDOWS:
    import pygetwindow as gw  # installed alongside pyautogui on Windows


class Spotify_Handler:
    def __init__(self, continue_checker, timeout_seconds=120):
        # continue_checker can be a bool or a callable returning a bool
        self.continue_checker = continue_checker
        self.timeout_seconds = timeout_seconds
        self.timeout = None
        self.spotify_program = "Spotify.exe" if IS_WINDOWS else "spotify"
        # True only when *we* paused Spotify at the start of a rest interval,
        # so we never resume playback the user paused themselves.
        self._paused_by_us = False
        # Spotify commands run on one background worker so the UI never blocks
        # and pause/resume requests are always executed in order.
        self._tasks = queue.Queue()
        self._worker = None
        self._worker_lock = threading.Lock()

    def _check_spotify_program(self) -> bool:
        """Return True if a Spotify process is currently running."""
        return bool(self._spotify_pids())

    # ---------- window helpers ----------
    def _spotify_pids(self) -> set:
        target = self.spotify_program.lower()
        pids = set()
        for proc in psutil.process_iter(["name"]):
            try:
                if (proc.info["name"] or "").lower() == target:
                    pids.add(proc.pid)
            except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
                continue
        return pids

    def _get_spotify_window(self):
        """Windows only: find the Spotify main window.

        The title is "Spotify Premium"/"Spotify Free" when paused but becomes
        "Artist - Song" while playing, so we match on the owning process instead.
        """
        import ctypes
        from ctypes import wintypes

        pids = self._spotify_pids()
        for win in gw.getAllWindows():
            if not win.title:
                continue  # Spotify spawns several hidden, untitled windows
            pid = wintypes.DWORD()
            ctypes.windll.user32.GetWindowThreadProcessId(win._hWnd, ctypes.byref(pid))
            if pid.value in pids:
                return win
        return None

    def _focus_spotify(self):
        """Bring Spotify to the foreground. Returns a handle used to minimize later, or None."""
        if IS_WINDOWS:
            win = self._get_spotify_window()
            if win is None:
                return None
            try:
                if win.isMinimized:
                    win.restore()
                win.activate()
            except Exception:
                # activate() can raise even when it succeeds on some Windows setups
                pass
            return win
        # Linux (X11): use xdotool
        try:
            result = subprocess.run(
                ["xdotool", "search", "--onlyvisible", "--class", "spotify"],
                capture_output=True, text=True, check=False,
            )
            window_ids = result.stdout.split()
            if not window_ids:
                return None
            win_id = window_ids[-1]
            subprocess.run(["xdotool", "windowactivate", "--sync", win_id], check=False)
            return win_id
        except FileNotFoundError:
            return None

    def _minimize_spotify(self, handle):
        if handle is None:
            return
        if IS_WINDOWS:
            try:
                handle.minimize()
            except Exception:
                pass
        else:
            subprocess.run(["xdotool", "windowminimize", handle], check=False)

    # ---------- Linux: MPRIS / D-Bus (no xdotool, no window focus needed) ----------
    MPRIS_COMMANDS = [
        ["playerctl", "--player=spotify", "play-pause"],
        ["gdbus", "call", "--session",
         "--dest", "org.mpris.MediaPlayer2.spotify",
         "--object-path", "/org/mpris/MediaPlayer2",
         "--method", "org.mpris.MediaPlayer2.Player.PlayPause"],
        ["dbus-send", "--print-reply", "--session",
         "--dest=org.mpris.MediaPlayer2.spotify",
         "/org/mpris/MediaPlayer2",
         "org.mpris.MediaPlayer2.Player.PlayPause"],
    ]

    def _toggle_via_mpris(self) -> bool:
        """Send PlayPause to Spotify over D-Bus. Works on Wayland and with Snap/Flatpak Spotify.

        Tries playerctl, then gdbus, then dbus-send (whichever is installed).
        Returns True if one of them succeeded.
        """
        for cmd in self.MPRIS_COMMANDS:
            try:
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
            except (FileNotFoundError, subprocess.TimeoutExpired):
                continue  # tool not installed / hung - try the next one
            if result.returncode == 0:
                return True
        return False

    def _toggle_via_window(self) -> bool:
        """Focus Spotify, press space, minimize it again. Returns True on success."""
        handle = self._focus_spotify()
        if handle is None:
            return False
        time.sleep(0.5)  # give the window time to take focus
        pyautogui.press("space")
        time.sleep(0.3)
        self._minimize_spotify(handle)
        return True

    # ---------- main entry ----------
    def start_handler(self):
        """If Spotify is running, toggle play/pause.

        Linux: uses MPRIS over D-Bus first (no window juggling), falling back to xdotool.
        Windows: focuses Spotify, presses space, then minimizes it.
        """
        if not self._check_spotify_program():
            print("Spotify not open")
            return  # Spotify isn't open - nothing to do
        self.timeout = time.time() + self.timeout_seconds
        while self.continue_checker and time.time() < self.timeout:
            if not IS_WINDOWS and self._toggle_via_mpris():
                return
            if self._toggle_via_window():
                return
            # Spotify still starting up / D-Bus name not registered yet - retry shortly
            time.sleep(1)

    # ---------- playback state (never toggles blindly) ----------
    MPRIS_DEST = "org.mpris.MediaPlayer2.spotify"
    MPRIS_PATH = "/org/mpris/MediaPlayer2"
    MPRIS_IFACE = "org.mpris.MediaPlayer2.Player"

    def _mpris_status_commands(self):
        return [
            ["playerctl", "--player=spotify", "status"],
            ["gdbus", "call", "--session", "--dest", self.MPRIS_DEST,
             "--object-path", self.MPRIS_PATH,
             "--method", "org.freedesktop.DBus.Properties.Get",
             self.MPRIS_IFACE, "PlaybackStatus"],
            ["dbus-send", "--print-reply", "--session", f"--dest={self.MPRIS_DEST}",
             self.MPRIS_PATH, "org.freedesktop.DBus.Properties.Get",
             f"string:{self.MPRIS_IFACE}", "string:PlaybackStatus"],
        ]

    def _mpris_action_commands(self, action):
        """action is 'Play' or 'Pause' - explicit, idempotent MPRIS methods (not PlayPause)."""
        return [
            ["playerctl", "--player=spotify", action.lower()],
            ["gdbus", "call", "--session", "--dest", self.MPRIS_DEST,
             "--object-path", self.MPRIS_PATH,
             "--method", f"{self.MPRIS_IFACE}.{action}"],
            ["dbus-send", "--print-reply", "--session", f"--dest={self.MPRIS_DEST}",
             self.MPRIS_PATH, f"{self.MPRIS_IFACE}.{action}"],
        ]

    @staticmethod
    def _run_first_success(commands):
        """Run commands in order, returning stdout of the first that succeeds, else None."""
        for cmd in commands:
            try:
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
            except (FileNotFoundError, subprocess.TimeoutExpired):
                continue
            if result.returncode == 0:
                return result.stdout
        return None

    def _status_via_mpris(self):
        out = self._run_first_success(self._mpris_status_commands())
        if out is None:
            return None
        for status in ("Playing", "Paused", "Stopped"):
            if status in out:
                return status
        return None

    def _spotify_window_titles(self) -> list:
        if IS_WINDOWS:
            win = self._get_spotify_window()
            return [win.title] if win is not None and win.title else []
        try:
            result = subprocess.run(["xdotool", "search", "--class", "spotify"],
                                    capture_output=True, text=True, check=False, timeout=3)
            titles = []
            for win_id in result.stdout.split():
                name = subprocess.run(["xdotool", "getwindowname", win_id],
                                      capture_output=True, text=True, check=False, timeout=3)
                if name.stdout.strip():
                    titles.append(name.stdout.strip())
            return titles
        except (FileNotFoundError, subprocess.TimeoutExpired):
            return []

    def _status_via_window(self):
        """Spotify's window title is 'Spotify Premium/Free' when paused, 'Artist - Song' when playing."""
        titles = self._spotify_window_titles()
        if any(not t.startswith("Spotify") and " - " in t for t in titles):
            return "Playing"
        if any(t.startswith("Spotify") for t in titles):
            return "Paused"
        return None  # unknown

    def get_playback_status(self):
        """Return 'Playing', 'Paused', 'Stopped' or None if it can't be determined."""
        if not IS_WINDOWS:
            status = self._status_via_mpris()
            if status is not None:
                return status
        return self._status_via_window()

    def _set_playing(self, play: bool) -> bool:
        """Put Spotify into the requested state without ever blindly toggling."""
        if not IS_WINDOWS:
            if self._run_first_success(self._mpris_action_commands("Play" if play else "Pause")) is not None:
                return True
        # Window fallback only has a toggle (space), so only press it when the
        # current state is known and differs from the requested one.
        status = self._status_via_window()
        if status is None:
            return False
        if (status == "Playing") == play:
            return True
        return self._toggle_via_window()

    # ---------- rest interval entry points ----------
    def pause_for_rest(self):
        """Call when a rest interval starts. Pauses only if Spotify is currently playing."""
        self._submit(self._do_pause_for_rest)

    def resume_after_rest(self):
        """Call when a rest interval ends. Resumes only if we paused it at rest start."""
        self._submit(self._do_resume_after_rest)

    def wait_until_idle(self, timeout=5.0):
        """Block until queued Spotify commands are done (e.g. before the app exits)."""
        done = threading.Event()
        self._submit(done.set)
        done.wait(timeout)

    def _do_pause_for_rest(self):
        self._paused_by_us = False
        if not self._check_spotify_program():
            return
        if self.get_playback_status() != "Playing":
            return  # already paused / stopped / unknown - leave it alone
        if self._set_playing(False):
            self._paused_by_us = True

    def _do_resume_after_rest(self):
        if not self._paused_by_us:
            return  # user had Spotify paused before the rest - don't start it
        self._paused_by_us = False
        if not self._check_spotify_program():
            return
        if self.get_playback_status() != "Paused":
            return  # user already resumed it (or state unknown) - don't touch it
        self._set_playing(True)

    # ---------- background worker ----------
    def _submit(self, fn):
        with self._worker_lock:
            if self._worker is None or not self._worker.is_alive():
                self._worker = threading.Thread(target=self._run_worker, daemon=True)
                self._worker.start()
        self._tasks.put(fn)

    def _run_worker(self):
        while True:
            fn = self._tasks.get()
            try:
                fn()
            except Exception as e:
                print(f"Spotify handler error: {e}")
