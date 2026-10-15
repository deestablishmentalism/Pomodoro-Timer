"""Path / environment helpers that work both from source and from a PyInstaller bundle."""
import os
import sys

IS_FROZEN = getattr(sys, "frozen", False)


def get_base_path() -> str:
    """Directory that contains the ``assets/`` folder.

    - From source: the project root (one level above ``src/``).
    - Frozen (PyInstaller): the bundle data dir (``sys._MEIPASS``, i.e. ``_internal/``
      in onedir builds), falling back to the executable's directory.
    """
    if IS_FROZEN:
        return getattr(sys, "_MEIPASS", os.path.dirname(os.path.abspath(sys.executable)))
    # src/utils/paths.py -> src/utils -> src -> project root
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def get_resource_path(relative_path: str) -> str:
    """Absolute path to a bundled resource (e.g. ``"assets/timer-logo.png"``)."""
    return os.path.join(get_base_path(), *relative_path.replace("\\", "/").split("/"))


def restore_child_environment() -> None:
    """Undo PyInstaller's library-path changes so external tools run with the host libraries.

    On Linux the PyInstaller bootloader points ``LD_LIBRARY_PATH`` at the bundle, which is
    inherited by subprocesses (playerctl, mpv, vlc, xdotool, ...) and can make them load our
    bundled (possibly incompatible) libraries. The original value is kept in
    ``LD_LIBRARY_PATH_ORIG``. The dynamic loader of *this* process read the variable at
    startup, so changing ``os.environ`` here only affects child processes.
    """
    if not IS_FROZEN or sys.platform == "win32":
        return
    for var in ("LD_LIBRARY_PATH",):
        original = os.environ.pop(var + "_ORIG", None)
        if original is not None:
            os.environ[var] = original
        else:
            os.environ.pop(var, None)

