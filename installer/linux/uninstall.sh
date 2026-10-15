#!/usr/bin/env bash
# Pomodoro Timer - Linux uninstaller
# Removes everything created by install.sh. System packages (python3-tk,
# playerctl, mpv, ...) are left alone since other programs may use them.
#
# Usage: ./uninstall.sh [--yes]
set -euo pipefail

APP_ID="pomodoro-timer"
APP_NAME="Pomodoro Timer"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="$DATA_HOME/$APP_ID"
LAUNCHER="$HOME/.local/bin/$APP_ID"
DESKTOP_FILE="$DATA_HOME/applications/$APP_ID.desktop"

ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

if [ ! -e "$APP_DIR" ] && [ ! -e "$LAUNCHER" ] && [ ! -e "$DESKTOP_FILE" ]; then
    echo "$APP_NAME does not appear to be installed."
    exit 0
fi

if [ "$ASSUME_YES" -ne 1 ]; then
    echo "This will remove:"
    for p in "$APP_DIR" "$LAUNCHER" "$DESKTOP_FILE"; do [ -e "$p" ] && echo "    $p"; done
    read -r -p "Continue? [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

# Close the app if it is running (so no files are in use) - binary build or source install
for pattern in "$APP_DIR/bin/pomodoro-timer" "$APP_DIR/app/main.py"; do
    if pgrep -f "$pattern" >/dev/null 2>&1; then
        info "Closing running $APP_NAME..."
        pkill -f "$pattern" || true
        sleep 1
    fi
done

# Leave the install dir before deleting it (this script may live inside it)
cd "$HOME"

info "Removing files..."
rm -f "$LAUNCHER" "$DESKTOP_FILE"
rm -rf "$APP_DIR"
command -v update-desktop-database >/dev/null 2>&1 \
    && update-desktop-database "$(dirname "$DESKTOP_FILE")" >/dev/null 2>&1 || true

info "$APP_NAME uninstalled."

