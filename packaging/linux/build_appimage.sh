#!/usr/bin/env bash
# Pomodoro Timer - wrap the PyInstaller onedir build (dist/pomodoro-timer/) into an AppImage.
#
# Usage: packaging/linux/build_appimage.sh
#   Env: APPIMAGETOOL=/path/to/appimagetool   use a specific appimagetool
#        (otherwise uses one on PATH, or downloads it into build/tools/)
# Output: dist/PomodoroTimer-<arch>.AppImage
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DIST="$ROOT/dist"
ARCH="$(uname -m)"
APPDIR="$ROOT/build/PomodoroTimer.AppDir"
OUT="$DIST/PomodoroTimer-$ARCH.AppImage"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

[ -x "$DIST/pomodoro-timer/pomodoro-timer" ] \
    || { echo "Build dist/pomodoro-timer first (packaging/linux/build_linux.sh)." >&2; exit 1; }

# ---------- appimagetool ----------
TOOL="${APPIMAGETOOL:-}"
if [ -z "$TOOL" ]; then
    if command -v appimagetool >/dev/null 2>&1; then
        TOOL="$(command -v appimagetool)"
    else
        TOOL="$ROOT/build/tools/appimagetool-$ARCH.AppImage"
        if [ ! -x "$TOOL" ]; then
            info "Downloading appimagetool"
            mkdir -p "$(dirname "$TOOL")"
            curl -fL --retry 3 -o "$TOOL" \
                "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$ARCH.AppImage"
            chmod +x "$TOOL"
        fi
    fi
fi

# ---------- AppDir ----------
info "Assembling AppDir"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" "$APPDIR/usr/share/icons/hicolor/256x256/apps"
cp -a "$DIST/pomodoro-timer" "$APPDIR/usr/bin/pomodoro-timer"

ICON_SRC="$ROOT/assets/timer-logo-256.png"
[ -f "$ICON_SRC" ] || ICON_SRC="$ROOT/assets/timer-logo.png"
cp "$ICON_SRC" "$APPDIR/pomodoro-timer.png"
cp "$ICON_SRC" "$APPDIR/usr/share/icons/hicolor/256x256/apps/pomodoro-timer.png"
ln -s pomodoro-timer.png "$APPDIR/.DirIcon"

cat > "$APPDIR/pomodoro-timer.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Pomodoro Timer
Comment=Focus timer with Spotify control and rest-interval media
Exec=pomodoro-timer
Icon=pomodoro-timer
Terminal=false
Categories=Utility;
Keywords=pomodoro;timer;focus;productivity;
EOF
cp "$APPDIR/pomodoro-timer.desktop" "$APPDIR/usr/share/applications/"

cat > "$APPDIR/AppRun" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "${0}")")"
exec "${HERE}/usr/bin/pomodoro-timer/pomodoro-timer" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# ---------- Build ----------
info "Building $(basename "$OUT")"
mkdir -p "$DIST"
# APPIMAGE_EXTRACT_AND_RUN lets appimagetool (itself an AppImage) run without FUSE (CI, containers)
ARCH="$ARCH" APPIMAGE_EXTRACT_AND_RUN=1 "$TOOL" --no-appstream "$APPDIR" "$OUT"
chmod +x "$OUT"
info "Wrote $OUT"

