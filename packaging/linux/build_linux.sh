#!/usr/bin/env bash
# Pomodoro Timer - build the standalone Linux packages (no Python needed on target machines).
#
# Produces in dist/:
#   pomodoro-timer/                         PyInstaller onedir build
#   pomodoro-timer-linux-x86_64.tar.gz      portable build + offline install.sh / uninstall.sh
#   PomodoroTimer-x86_64.AppImage           single-file app (unless --no-appimage)
#
# Usage: packaging/linux/build_linux.sh [--python PATH] [--skip-pyinstaller] [--no-appimage]
#   --python PATH        Python interpreter with requirements-dev.txt installed
#                        (default: .venv/bin/python if present, else python3)
#   --skip-pyinstaller   reuse an existing dist/pomodoro-timer/
#   --no-appimage        only build the tarball
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DIST="$ROOT/dist"
ARCH="$(uname -m)"

PYTHON=""
SKIP_PYI=0
APPIMAGE=1
while [ $# -gt 0 ]; do
    case "$1" in
        --python) PYTHON="$2"; shift ;;
        --skip-pyinstaller) SKIP_PYI=1 ;;
        --no-appimage) APPIMAGE=0 ;;
        -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done
if [ -z "$PYTHON" ]; then
    if [ -x "$ROOT/.venv/bin/python" ]; then PYTHON="$ROOT/.venv/bin/python"; else PYTHON="python3"; fi
fi

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

cd "$ROOT"

# ---------- 1. PyInstaller onedir build ----------
if [ "$SKIP_PYI" -eq 0 ]; then
    info "Building with PyInstaller ($("$PYTHON" --version 2>&1))"
    "$PYTHON" -m PyInstaller --version >/dev/null 2>&1 \
        || { echo "PyInstaller not found. Run: $PYTHON -m pip install -r requirements-dev.txt" >&2; exit 1; }
    "$PYTHON" -m PyInstaller --noconfirm --clean --distpath "$DIST" --workpath "$ROOT/build" pomodoro-timer.spec
fi
[ -x "$DIST/pomodoro-timer/pomodoro-timer" ] || { echo "dist/pomodoro-timer/pomodoro-timer missing" >&2; exit 1; }

# ---------- 2. Portable tarball (binary + offline installer) ----------
PKG="pomodoro-timer-linux-$ARCH"
STAGE="$ROOT/build/$PKG"
info "Creating $PKG.tar.gz"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -a "$DIST/pomodoro-timer" "$STAGE/pomodoro-timer"
cp "$ROOT/installer/linux/install.sh" "$ROOT/installer/linux/uninstall.sh" "$STAGE/"
chmod +x "$STAGE/install.sh" "$STAGE/uninstall.sh"
cat > "$STAGE/README.txt" <<'EOF'
Pomodoro Timer - portable Linux build (no Python required)

Run without installing:   ./pomodoro-timer/pomodoro-timer
Install for this user:    ./install.sh        (app menu entry + `pomodoro-timer` command)
Uninstall:                ~/.local/share/pomodoro-timer/uninstall.sh

Optional tools: playerctl (Spotify control), mpv / ffmpeg / vlc (rest media).
EOF
tar -C "$ROOT/build" -czf "$DIST/$PKG.tar.gz" "$PKG"

# ---------- 3. AppImage ----------
if [ "$APPIMAGE" -eq 1 ]; then
    "$SCRIPT_DIR/build_appimage.sh"
fi

info "Done. Artifacts in $DIST:"
ls -lh "$DIST" | sed -n '2,$p'

