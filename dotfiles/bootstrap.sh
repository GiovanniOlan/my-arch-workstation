#!/usr/bin/env bash
#
# Entry point for Part 2 on a machine that does not have chezmoi yet, which is
# every freshly installed one. This is the only script of the project that runs
# outside chezmoi, for the obvious reason that chezmoi cannot install itself.
#
# Run it from a clone of this repository:
#
#     bash dotfiles/bootstrap.sh
#
# It points chezmoi at this clone's dotfiles/ directory, so the repository you
# are looking at is the one that gets applied. On a machine where chezmoi is
# already installed and you would rather have it manage its own clone, use
# `chezmoi init --apply <repository-url>` instead: the .chezmoiroot file at the
# repository root makes it find dotfiles/ on its own.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/log.sh
source "$SCRIPT_DIR/../lib/log.sh"

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

warn "The next step installs packages, enables services and writes to /etc."

info "Initialising chezmoi from $SCRIPT_DIR ..."

chezmoi init --apply --source "$SCRIPT_DIR"

ok "Desktop provisioned. Reboot to start the session from tty1."
