#!/usr/bin/env bash
# netbird-summary installer
# Clones (or updates) netbird-summary from GitHub, symlinks the command into a
# bin directory appropriate for the detected OS, and ensures it is on your PATH.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/jarrah31/netbird-summary/main/install.sh | bash
#
# Optional overrides (env vars):
#   NETBIRD_SUMMARY_DIR   where to clone the repo (default: ~/.local/share/netbird-summary)
#   NETBIRD_SUMMARY_BIN   bin dir for the symlink (default: chosen per OS)

set -euo pipefail

REPO_URL="https://github.com/jarrah31/netbird-summary.git"
INSTALL_DIR="${NETBIRD_SUMMARY_DIR:-$HOME/.local/share/netbird-summary}"
SCRIPT_NAME="netbird-summary"

# ── Colors (only when writing to a terminal) ────────────────────────────────────
if [ -t 1 ]; then
    BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
    RED=$'\033[31m'; CYAN=$'\033[36m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
    BOLD=""; GREEN=""; YELLOW=""; RED=""; CYAN=""; DIM=""; RESET=""
fi

info() { printf '  %s\n' "$*"; }
ok()   { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$*"; }
die()  { printf '  %s✗ %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }

printf '\n  %s%sInstalling netbird-summary%s\n\n' "$BOLD" "$CYAN" "$RESET"

# ── Prerequisites ───────────────────────────────────────────────────────────────
command -v git >/dev/null 2>&1 || \
    die "git is required but not found. Install git and re-run this installer."

# ── Clone or update the repo ────────────────────────────────────────────────────
if [ -d "$INSTALL_DIR/.git" ]; then
    info "Updating existing install in $INSTALL_DIR …"
    git -C "$INSTALL_DIR" pull --ff-only --quiet || \
        die "Failed to update the existing repo in $INSTALL_DIR"
    ok "Updated to the latest version"
elif [ -e "$INSTALL_DIR" ]; then
    die "$INSTALL_DIR already exists but is not a git checkout. Remove it and re-run."
else
    info "Cloning into $INSTALL_DIR …"
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone --depth 1 --quiet "$REPO_URL" "$INSTALL_DIR" || \
        die "Failed to clone $REPO_URL"
    ok "Cloned netbird-summary"
fi

chmod +x "$INSTALL_DIR/$SCRIPT_NAME.sh"

# ── Choose a bin directory based on the detected OS ──────────────────────────────
os=$(uname -s)
if [ -n "${NETBIRD_SUMMARY_BIN:-}" ]; then
    BIN_DIR="$NETBIRD_SUMMARY_BIN"
else
    case "$os" in
        Linux|Darwin)
            # Prefer /usr/local/bin when we can write to it without sudo,
            # otherwise fall back to the per-user ~/.local/bin.
            if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
                BIN_DIR="/usr/local/bin"
            else
                BIN_DIR="$HOME/.local/bin"
            fi
            ;;
        MINGW*|MSYS*|CYGWIN*)   # Windows: Git Bash / MSYS2
            BIN_DIR="$HOME/bin"
            ;;
        *)
            BIN_DIR="$HOME/.local/bin"
            ;;
    esac
fi

info "Detected OS: ${BOLD}${os}${RESET}  →  bin directory: ${BOLD}${BIN_DIR}${RESET}"
mkdir -p "$BIN_DIR"

# ── Create the symlink ──────────────────────────────────────────────────────────
LINK="$BIN_DIR/$SCRIPT_NAME"
ln -sf "$INSTALL_DIR/$SCRIPT_NAME.sh" "$LINK"
ok "Linked $LINK → $INSTALL_DIR/$SCRIPT_NAME.sh"

# ── Ensure the bin directory is on PATH ──────────────────────────────────────────
case ":$PATH:" in
    *":$BIN_DIR:"*)
        ok "$BIN_DIR is already on your PATH"
        NEEDS_PATH=""
        ;;
    *)
        NEEDS_PATH="yes"
        ;;
esac

if [ -n "$NEEDS_PATH" ]; then
    shell_name=$(basename "${SHELL:-}")
    case "$shell_name" in
        zsh)  rc="$HOME/.zshrc"   ;;
        bash) rc="$HOME/.bashrc"  ;;
        *)    rc="$HOME/.profile" ;;
    esac

    line="export PATH=\"$BIN_DIR:\$PATH\""
    if grep -qsF "$line" "$rc" 2>/dev/null; then
        warn "$BIN_DIR not active in this shell yet — run: ${BOLD}source $rc${RESET}"
    else
        printf '\n# Added by netbird-summary installer\n%s\n' "$line" >> "$rc"
        ok "Added $BIN_DIR to PATH in $rc"
        warn "Run ${BOLD}source $rc${RESET} (or open a new terminal) to use it now"
    fi
fi

# ── Done ────────────────────────────────────────────────────────────────────────
printf '\n  %s%sInstalled.%s Run %snetbird-summary%s to get started.\n\n' \
    "$BOLD" "$GREEN" "$RESET" "$BOLD" "$RESET"
