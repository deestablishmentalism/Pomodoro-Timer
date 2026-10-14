#!/usr/bin/env bash
# Pomodoro Timer - Linux installer (per-user, no root needed for the app itself)
#
# Installs to:
#   ~/.local/share/pomodoro-timer/        app code + private virtualenv
#   ~/.local/bin/pomodoro-timer           launcher command
#   ~/.local/share/applications/pomodoro-timer.desktop   app-menu entry
#
# Usage: ./install.sh [--yes]     (--yes = answer "yes" to every prompt)
set -euo pipefail

APP_ID="pomodoro-timer"
APP_NAME="Pomodoro Timer"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="$DATA_HOME/$APP_ID"
BIN_DIR="$HOME/.local/bin"
LAUNCHER="$BIN_DIR/$APP_ID"
DESKTOP_FILE="$DATA_HOME/applications/$APP_ID.desktop"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MIN_PY_MINOR=8   # Python 3.8+

ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes) ASSUME_YES=1 ;;
        -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }
confirm() {
    [ "$ASSUME_YES" -eq 1 ] && return 0
    [ -t 0 ] || return 1
    read -r -p "$1 [y/N] " reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

# ---------- package manager helpers ----------
detect_pm() {
    for pm in apt-get dnf pacman zypper; do
        command -v "$pm" >/dev/null 2>&1 && { echo "$pm"; return; }
    done
    echo ""
}
PM="$(detect_pm)"

# Map a generic dependency name to the distro package name
pkg_name() {
    case "$1:$PM" in
        tk:apt-get)  echo python3-tk ;;
        tk:dnf)      echo python3-tkinter ;;
        tk:pacman)   echo tk ;;
        tk:zypper)   echo python3-tk ;;
        venv:apt-get) echo python3-venv ;;
        venv:*)      echo "" ;;          # bundled with python on other distros
        *)           echo "$1" ;;        # playerctl, mpv, xdotool share names
    esac
}

pm_install() {
    [ $# -eq 0 ] && return 0
    local sudo=""
    [ "$(id -u)" -ne 0 ] && sudo="sudo"
    case "$PM" in
        apt-get) $sudo apt-get update && $sudo apt-get install -y "$@" ;;
        dnf)     $sudo dnf install -y "$@" ;;
        pacman)  $sudo pacman -S --needed --noconfirm "$@" ;;
        zypper)  $sudo zypper install -y "$@" ;;
        *)       return 1 ;;
    esac
}

# ---------- 1. Python ----------
info "Checking Python..."
PYTHON="$(command -v python3 || true)"
[ -n "$PYTHON" ] || die "python3 not found. Install Python 3.$MIN_PY_MINOR+ and re-run."
"$PYTHON" -c "import sys; sys.exit(0 if sys.version_info >= (3, $MIN_PY_MINOR) else 1)" \
    || die "Python 3.$MIN_PY_MINOR+ required (found $("$PYTHON" --version 2>&1))."
echo "    $("$PYTHON" --version 2>&1) at $PYTHON"

# ---------- 2. Required system packages (tkinter, venv) ----------
missing=()
"$PYTHON" -c "import tkinter" 2>/dev/null || missing+=("$(pkg_name tk)")
"$PYTHON" -c "import ensurepip, venv" 2>/dev/null || {
    p="$(pkg_name venv)"; [ -n "$p" ] && missing+=("$p")
}
if [ ${#missing[@]} -gt 0 ]; then
    warn "Missing required system packages: ${missing[*]}"
    if [ -n "$PM" ] && confirm "Install them now with $PM (needs sudo)?"; then
        pm_install "${missing[@]}" || die "Failed to install ${missing[*]}"
    else
        die "Please install: ${missing[*]} and re-run this installer."
    fi
fi

# ---------- 3. Optional tools (Spotify control + rest media) ----------
optional=()
command -v playerctl >/dev/null 2>&1 || optional+=(playerctl)   # Spotify pause/resume
command -v xdotool   >/dev/null 2>&1 || optional+=(xdotool)     # Spotify fallback (X11)
if ! command -v mpv >/dev/null 2>&1 && ! command -v ffplay >/dev/null 2>&1 \
   && ! command -v vlc >/dev/null 2>&1 && ! command -v cvlc >/dev/null 2>&1; then
    optional+=(mpv)                                              # rest media player
fi
if [ ${#optional[@]} -gt 0 ]; then
    echo "    Optional tools not found: ${optional[*]}"
    echo "    (playerctl/xdotool = Spotify control, mpv = rest-interval media)"
    if [ -n "$PM" ] && confirm "Install optional tools with $PM (needs sudo)?"; then
        pm_install "${optional[@]}" || warn "Could not install optional tools - continuing."
    fi
fi

# ---------- 4. Copy app ----------
info "Installing app to $APP_DIR"
mkdir -p "$APP_DIR"
rm -rf "$APP_DIR/app"
cp -r "$REPO_ROOT/src" "$APP_DIR/app"
find "$APP_DIR/app" -name '__pycache__' -type d -prune -exec rm -rf {} +
rm -rf "$APP_DIR/assets"
[ -d "$REPO_ROOT/assets" ] && cp -r "$REPO_ROOT/assets" "$APP_DIR/assets"
cp "$REPO_ROOT/requirements.txt" "$APP_DIR/requirements.txt"
cp "$SCRIPT_DIR/uninstall.sh" "$APP_DIR/uninstall.sh"
chmod +x "$APP_DIR/uninstall.sh"

# ---------- 5. Virtualenv + Python deps ----------
VENV="$APP_DIR/venv"
if [ ! -x "$VENV/bin/python" ] || ! "$VENV/bin/python" -c "import sys" 2>/dev/null; then
    info "Creating virtual environment..."
    rm -rf "$VENV"
    "$PYTHON" -m venv "$VENV"
fi
info "Installing Python dependencies..."
"$VENV/bin/python" -m pip install --upgrade pip --quiet
"$VENV/bin/python" -m pip install -r "$APP_DIR/requirements.txt" --quiet

# ---------- 6. Launcher ----------
info "Creating launcher $LAUNCHER"
mkdir -p "$BIN_DIR"
cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
cd "$APP_DIR/app"
exec "$VENV/bin/python" "$APP_DIR/app/main.py" "\$@"
EOF
chmod +x "$LAUNCHER"

# ---------- 7. Desktop entry ----------
info "Creating app-menu entry"
ICON="appointment-soon"
for candidate in "$APP_DIR/assets/timer-logo.png" "$APP_DIR/app/assets/timer-logo.png"; do
    [ -f "$candidate" ] && { ICON="$candidate"; break; }
done
mkdir -p "$(dirname "$DESKTOP_FILE")"
cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=$APP_NAME
Comment=Focus timer with Spotify control and rest-interval media
Exec=$LAUNCHER
Icon=$ICON
Terminal=false
Categories=Utility;
Keywords=pomodoro;timer;focus;productivity;
EOF
command -v update-desktop-database >/dev/null 2>&1 \
    && update-desktop-database "$(dirname "$DESKTOP_FILE")" >/dev/null 2>&1 || true

# ---------- Done ----------
echo
info "$APP_NAME installed."
echo "    Launch from your app menu, or run: $APP_ID"
echo "    Uninstall with: $APP_DIR/uninstall.sh"
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not on your PATH. Add this to ~/.bashrc (or your shell rc):"
       echo "        export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

