#!/usr/bin/env bash
#
# Entry point for Part 2: turns an existing Arch install into the workstation.
# This is the only script of the project that runs outside chezmoi, for the
# obvious reason that chezmoi cannot install itself.
#
# On a machine that does not have the repository, run it straight off the network:
#
#     bash <(curl -fsSL https://github.com/GiovanniOlan/my-arch-workstation/raw/main/dotfiles/bootstrap.sh)
#
# Process substitution rather than `curl … | bash`: with a pipe the script itself
# arrives on stdin and the prompts underneath — chezmoi's, sudo's — would read the
# pipe instead of the keyboard.
#
# From a clone it also works, and then that clone is what gets applied:
#
#     bash dotfiles/bootstrap.sh [--machine desktop|laptop]
#
# --machine skips the machine profile question. Part 1 passes it through when it
# chains this script into the first boot, having asked it back on the ISO.
set -euo pipefail

##############################################
# Message helpers
##############################################
# A copy of arch-install/log.sh, on purpose: see that file for why the entry
# points carry their own instead of loading it.

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

##############################################
# Arguments
##############################################

MACHINE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --machine)
            [[ $# -ge 2 ]] || die "--machine needs a value: desktop or laptop."
            MACHINE="$2"
            shift 2
            ;;
        *) die "Unknown option: $1. Usage: bootstrap.sh [--machine desktop|laptop]" ;;
    esac
done

if [[ -n "$MACHINE" && "$MACHINE" != "desktop" && "$MACHINE" != "laptop" ]]; then
    die "Invalid machine profile: '$MACHINE'. Use 'desktop' or 'laptop'."
fi

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
# chezmoi records this path as its source directory for good, so there is exactly
# one clone on the machine and it lives somewhere a person would look for it —
# this repository is not only dotfiles, it also carries Part 1 and the planning
# artefacts, and burying it in a hidden data directory invites a second clone that
# then drifts from the one being applied.

REPO_URL="${DOTFILES_REPO_URL:-https://github.com/GiovanniOlan/my-arch-workstation.git}"
REPO_DIR="$HOME/workspaces/$(basename "$REPO_URL" .git)"

# Already inside a clone? Only when this file is a real file with the repository
# around it. Fetched over the network it is a pipe, and there is nothing around it.
if [[ -f "${BASH_SOURCE[0]}" ]]; then
    CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)" || CANDIDATE=""
    if [[ -n "$CANDIDATE" && -f "$CANDIDATE/.chezmoiroot" ]]; then
        REPO_DIR="$CANDIDATE"
    fi
fi

if [[ -d "$REPO_DIR/.git" ]]; then
    ok "Using the clone already at $REPO_DIR."
    # No pull on purpose. Updating the clone is the user's call, and pulling over
    # uncommitted work is a quiet way to lose it.
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

info "Initialising chezmoi from $REPO_DIR/dotfiles ..."

INIT_ARGS=(init --apply --source "$REPO_DIR/dotfiles")
if [[ -n "$MACHINE" ]]; then
    # Feeds promptChoiceOnce in .chezmoi.toml.tmpl, so the question never shows up.
    # Without it the prompt behaves exactly as it always has.
    INIT_ARGS+=(--promptChoice "machine=$MACHINE")
fi

chezmoi "${INIT_ARGS[@]}"

ok "Desktop provisioned. Reboot to start the session from tty1."
