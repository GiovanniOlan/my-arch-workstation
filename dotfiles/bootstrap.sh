#!/usr/bin/env bash

set -euo pipefail

##############################################
# Message helpers
##############################################

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

info() { echo -e "${BOLD}:: $*${RESET}"; }
ok() { echo -e "${GREEN}[✓] $*${RESET}"; }
warn() { echo -e "${YELLOW}[!] $*${RESET}"; }
die() {
    echo -e "${RED}[✗] $*${RESET}" >&2
    exit 1
}

[[ $# -eq 0 ]] || die "bootstrap.sh takes no arguments, got: $1"

##############################################
# Log
##############################################

LOG_FILE="$HOME/.local/state/dotfiles-bootstrap.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

echo
info "Bootstrap: $(date '+%Y-%m-%d %H:%M:%S')"
info "A copy of this run is kept at $LOG_FILE"

##############################################
# Host system
##############################################

info "Checking the host system..."

[[ $EUID -eq 0 ]] && die "Run as your own user, not as root."

command -v pacman >/dev/null 2>&1 || die "This setup targets Arch Linux: pacman was not found."

command -v sudo >/dev/null 2>&1 || die "sudo is required to install packages."

ping -c1 -W3 archlinux.org >/dev/null 2>&1 || die "No internet connection."

ok "Host system looks usable."

if command -v chezmoi >/dev/null 2>&1; then
    ok "chezmoi already installed."
else
    info "Installing chezmoi..."
    sudo pacman -S --needed --noconfirm chezmoi
    ok "chezmoi installed."
fi

##############################################
# The repository
##############################################


REPO_URL="${DOTFILES_REPO_URL:-https://github.com/GiovanniOlan/my-arch-workstation.git}"
REPO_DIR="$HOME/workspaces/$(basename "$REPO_URL" .git)"

if [[ -f "${BASH_SOURCE[0]}" ]]; then
    CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)" || CANDIDATE=""
    if [[ -n "$CANDIDATE" && -f "$CANDIDATE/.chezmoiroot" ]]; then
        REPO_DIR="$CANDIDATE"
    fi
fi

if [[ -d "$REPO_DIR/.git" ]]; then
    ok "Using the clone already at $REPO_DIR."
elif [[ -e "$REPO_DIR" ]]; then
    die "$REPO_DIR exists but is not a git clone. Move it aside and run this again."
else
    if ! command -v git >/dev/null 2>&1; then
        info "Installing git..."
        sudo pacman -S --needed --noconfirm git
    fi
    info "Cloning $REPO_URL into $REPO_DIR ..."
    mkdir -p "$(dirname "$REPO_DIR")"
    git clone "$REPO_URL" "$REPO_DIR"
    ok "Repository cloned. Edit, commit and push from there as usual."
fi

##############################################
# Apply
##############################################

warn "The next step installs packages, enables services and writes to /etc."

info "Elevated privileges are needed for packages and services."
sudo -v
while true; do
    sudo -n true
    sleep 50
    kill -0 "$$" 2>/dev/null || exit
done 2>/dev/null &

info "Initialising chezmoi from $REPO_DIR/dotfiles ..."

chezmoi init --apply --source "$REPO_DIR/dotfiles"

ok "Desktop provisioned. Reboot to start the session from tty1."
