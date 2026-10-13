"""Rest-interval media playback.

Plays random audio/video files from a user-selected directory while a rest
interval is running and stops them when the rest interval ends.

* Randomized order.
* In-session memory: files already played during this session are not
  repeated until every file has been played once (then the memory resets,
  never starting the new round with the file that just played).
* A directory with a single file loops that file for the whole rest interval.

Playback is delegated to an external player (mpv, ffplay or VLC - whichever
is installed), so no extra Python packages are required.
"""
import os
import platform
import random
import shutil
import subprocess
import threading

IS_WINDOWS = platform.system() == "Windows"

MEDIA_EXTENSIONS = {
    # audio
    ".mp3", ".wav", ".flac", ".ogg", ".oga", ".opus", ".m4a", ".aac", ".wma",
    # video
    ".mp4", ".mkv", ".webm", ".avi", ".mov", ".wmv", ".flv", ".m4v", ".mpg", ".mpeg",
}

# Extra install locations to probe on Windows when the player is not on PATH
WINDOWS_PLAYER_PATHS = {
    "vlc": [
        r"C:\Program Files\VideoLAN\VLC\vlc.exe",
        r"C:\Program Files (x86)\VideoLAN\VLC\vlc.exe",
    ],
}


class RestMediaHandler:
    POLL_SECONDS = 0.5

    def __init__(self, directory=None):
        self.directory = None
        self.files = []
        self.played = set()          # in-session memory of played files
        self.last_played = None
        self._process = None
        self._lock = threading.Lock()
        self._stop_event = threading.Event()
        self._watcher = None
        self._player = self._find_player()
        if directory:
            self.set_directory(directory)

    # ---------------- Configuration ----------------
    def set_directory(self, directory) -> int:
        """Scan ``directory`` (including subfolders) for media files. Returns the number found."""
        self.directory = directory
        found = []
        for root, dirs, names in os.walk(directory):
            dirs[:] = [d for d in dirs if not d.startswith(".")]  # skip hidden folders
            for name in names:
                if os.path.splitext(name)[1].lower() in MEDIA_EXTENSIONS:
                    found.append(os.path.join(root, name))
        self.files = sorted(found)
        self.reset_session()
        return len(self.files)

    def reset_session(self):
        """Forget which files were played (call when a new timer session starts)."""
        self.played.clear()
        self.last_played = None

    @property
    def has_media(self) -> bool:
        return bool(self.files)

    @property
    def player_name(self):
        return self._player[0] if self._player else None

    # ---------------- Public controls ----------------
    def start(self):
        """Begin playback - call when a rest interval starts."""
        if not self.files:
            return
        if not self._player:
            print("Rest media: no supported player found (install mpv, ffmpeg or VLC)")
            return
        self.stop()
        self._stop_event.clear()
        if len(self.files) == 1:
            # Single file: let the player loop it until the rest interval ends
            self._play(self.files[0], loop=True)
            return
        self._play(self._next_file())
        self._watcher = threading.Thread(target=self._watch, daemon=True)
        self._watcher.start()

    def stop(self):
        """Stop playback - call when the rest interval ends."""
        self._stop_event.set()
        with self._lock:
            proc, self._process = self._process, None
        self._terminate(proc)
        watcher, self._watcher = self._watcher, None
        if watcher is not None and watcher is not threading.current_thread():
            watcher.join(timeout=2)

    # ---------------- Internals ----------------
    def _next_file(self):
        """Pick a random file not yet played this session."""
        remaining = [f for f in self.files if f not in self.played]
        if not remaining:
            # Everything has played once: start a new round, but avoid
            # immediately repeating the file that just finished.
            self.played.clear()
            remaining = [f for f in self.files if f != self.last_played] or list(self.files)
        choice = random.choice(remaining)
        self.played.add(choice)
        self.last_played = choice
        return choice

    def _watch(self):
        """Start the next random file whenever the current one finishes."""
        while not self._stop_event.wait(self.POLL_SECONDS):
            with self._lock:
                proc = self._process
            if proc is not None and proc.poll() is not None:
                if self._stop_event.is_set():
                    break
                self._play(self._next_file())

    def _play(self, path, loop=False):
        name, exe = self._player
        cmd = self._build_command(name, exe, path, loop)
        kwargs = {"stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL, "stdin": subprocess.DEVNULL}
        if IS_WINDOWS:
            kwargs["creationflags"] = subprocess.CREATE_NO_WINDOW
        try:
            proc = subprocess.Popen(cmd, **kwargs)
        except OSError as e:
            print(f"Rest media: failed to start {name}: {e}")
            return
        with self._lock:
            if self._stop_event.is_set():
                # stop() was called while we were launching
                self._terminate(proc)
                return
            self._process = proc

    @staticmethod
    def _build_command(name, exe, path, loop):
        if name == "mpv":
            cmd = [exe, "--really-quiet", "--no-terminal"]
            if loop:
                cmd.append("--loop-file=inf")
        elif name == "ffplay":
            cmd = [exe, "-autoexit", "-loglevel", "quiet"]
            if loop:
                cmd += ["-loop", "0"]  # 0 = loop forever
        else:  # vlc / cvlc
            cmd = [exe, "--quiet"]
            cmd += ["--repeat"] if loop else ["--play-and-exit"]
        return cmd + [path]

    @staticmethod
    def _terminate(proc):
        if proc is None or proc.poll() is not None:
            return
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()

    @staticmethod
    def _find_player():
        """Return (name, executable) for the first available player, or None."""
        for name in ("mpv", "ffplay", "vlc", "cvlc"):
            exe = shutil.which(name)
            if exe:
                return ("vlc" if name == "cvlc" else name, exe)
            if IS_WINDOWS:
                for candidate in WINDOWS_PLAYER_PATHS.get(name, []):
                    if os.path.isfile(candidate):
                        return (name, candidate)
        return None

