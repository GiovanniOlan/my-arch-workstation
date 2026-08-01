#!/usr/bin/env bash
#
# Checks a machine that has just had Part 2 applied. Read-only: it inspects and
# reports, it never changes anything.
#
# Meant to be run inside the test VM straight from the shared repository, where
# typing a long command into a window with no clipboard is the main cost:
#
#     bash /repo/arch-install/dev/vm-check.sh
#
# Every check is reported on its own line and none of them abort the run, so a
# single pass shows everything that is wrong rather than only the first thing.

# No -e on purpose: a failing check must not end the run.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../log.sh
source "$SCRIPT_DIR/../log.sh"

failures=0

check() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        ok "$description"
    else
        warn "FAILED: $description"
        failures=$((failures + 1))
    fi
}

# Same, for what must NOT be there. A leading '!' cannot be passed to check:
# bash only treats it as negation when it parses it, not when it arrives as an
# argument, so it would be looked up as a command name.
check_absent() {
    local description="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        warn "FAILED: $description"
        failures=$((failures + 1))
    else
        ok "$description"
    fi
}

CHEZMOI_CONFIG="$HOME/.config/chezmoi/chezmoi.toml"

machine="$(sed -n 's/^[[:space:]]*machine[[:space:]]*=[[:space:]]*"\(.*\)"$/\1/p' "$CHEZMOI_CONFIG" 2>/dev/null)"
[[ -n "$machine" ]] || machine="unknown"

info "Checking a '$machine' machine."

##############################################
# chezmoi itself
##############################################

check "chezmoi is installed" command -v chezmoi
check "the config records sourceDir, so a bare 'chezmoi apply' works" \
    grep -q '^sourceDir' "$CHEZMOI_CONFIG"
check "the destination matches the source state (chezmoi verify)" chezmoi verify

##############################################
# Deployed files
##############################################

for config in hypr/keybinds.lua waybar/config.jsonc fuzzel/fuzzel.ini mako/config \
              wl-kbptr/config fontconfig/fonts.conf; do
    # shellcheck disable=SC2088  # the tilde is prose in the report line, not a path
    check "~/.config/$config is a regular file, not a link into a clone" \
        test -f "$HOME/.config/$config" -a ! -L "$HOME/.config/$config"
done

for script in action-menu dnd-toggle hypridle-toggle power-profile; do
    check "$script is on PATH and executable" test -x "$HOME/.local/bin/$script"
done

# shellcheck disable=SC2088  # the tilde is prose in the report line, not a path
check "~/.bash_profile starts the compositor on tty1" \
    grep -q 'start-hyprland' "$HOME/.bash_profile"

##############################################
# User directories
##############################################
# The failure this catches: xdg-user-dirs-update reassigning every directory to
# $HOME because none of them existed when it ran.

# shellcheck disable=SC2016  # the literal string $HOME is what is being grepped for
check "user directories point at real subdirectories, not at \$HOME" \
    grep -q 'XDG_DESKTOP_DIR="\$HOME/Desktop"' "$HOME/.config/user-dirs.dirs"

# Sourcing expands the $HOME in the values; re-reading yields the names.
# shellcheck source=/dev/null
. "$HOME/.config/user-dirs.dirs"
while IFS='=' read -r name _; do
    case "$name" in
        XDG_*_DIR) check "$name exists (${!name})" test -d "${!name}" ;;
    esac
done <"$HOME/.config/user-dirs.dirs"

##############################################
# Packages and services
##############################################

for package in hyprland hypridle hyprlock waybar fuzzel mako kitty grimblast-git; do
    check "$package installed" pacman -Q "$package"
done

for service in pipewire pipewire-pulse wireplumber; do
    check "user service $service enabled" systemctl --user is-enabled "$service"
done

for service in NetworkManager bluetooth power-profiles-daemon; do
    check "system service $service enabled" systemctl is-enabled "$service"
done

check "automatic login is configured on tty1" \
    grep -q -- '--autologin' /etc/systemd/system/getty@tty1.service.d/autologin.conf

##############################################
# Machine profile
##############################################
# The point of the profiles: a desktop must not carry what only a laptop has.

check "monitors.lua declares a catch-all output" \
    grep -q 'output   = ""' "$HOME/.config/hypr/monitors.lua"

if [[ "$machine" == "laptop" ]]; then
    check "laptop: brightness keybinds present" \
        grep -q 'brightnessctl' "$HOME/.config/hypr/keybinds.lua"
    check "laptop: battery module present in the bar" \
        grep -q '"battery"' "$HOME/.config/waybar/config.jsonc"
    check "laptop: touchpad configured" \
        grep -q 'touchpad' "$HOME/.config/hypr/input.lua"
    check "laptop: idle suspends the machine" \
        grep -q 'systemctl suspend' "$HOME/.config/hypr/hypridle.conf"
else
    check_absent "desktop: no brightness keybinds" \
        grep -q 'brightnessctl' "$HOME/.config/hypr/keybinds.lua"
    check_absent "desktop: no battery module in the bar" \
        grep -q '"battery"' "$HOME/.config/waybar/config.jsonc"
    check_absent "desktop: no touchpad configured" \
        grep -q 'touchpad' "$HOME/.config/hypr/input.lua"
    check_absent "desktop: idle does not suspend the machine" \
        grep -q 'systemctl suspend' "$HOME/.config/hypr/hypridle.conf"
fi

##############################################
# Result
##############################################

echo
if (( failures == 0 )); then
    ok "Everything checked out. Reboot to land on the desktop."
else
    die "$failures check(s) failed."
fi
