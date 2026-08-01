#!/usr/bin/env bash
#
# Runs on the first login of a machine installed with the chaining enabled, from
# the clone that the provisional ~/.bash_profile has just fetched. It is the whole
# handover: everything Part 1 seeded is consumed and cleaned up here.
#
# It is not an entry point — by the time it runs the repository is on disk — so it
# loads the message helpers instead of carrying a copy of them.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=./log.sh
source "$SCRIPT_DIR/log.sh"

STATE_DIR="$HOME/.local/state"
PENDING_FILE="$STATE_DIR/first-boot-pending"
LOG_FILE="$STATE_DIR/first-boot.log"
SUDOERS_DROPIN="/etc/sudoers.d/99-first-boot"

[[ -f "$PENDING_FILE" ]] || die "Nothing pending: $PENDING_FILE does not exist."

##############################################
# Privilege window
##############################################
# Part 1 left a passwordless sudo grant so that this first run needs nobody in
# front of the screen. Revoking it is tied to this process ending — any ending,
# including a failure or a Ctrl-C — rather than to reaching the end of the happy
# path, because the real risk is not the few minutes it lasts but leaving it
# behind forever after a crash.
#
# A retry therefore runs without it and asks for the password. That is correct:
# the first attempt is unattended by design, a retry is by definition attended.

revoke_privileges() {
    # The check has to go through sudo: /etc/sudoers.d is not readable by an
    # unprivileged user, so a plain test on the path would report "not there" even
    # when it is, and the grant would survive. -n keeps it non-interactive — on a
    # retry the grant is already gone, sudo has nothing to offer without a
    # password, and there is nothing left to revoke anyway.
    if sudo -n test -f "$SUDOERS_DROPIN" 2>/dev/null; then
        sudo -n rm -f "$SUDOERS_DROPIN" 2>/dev/null \
            || warn "Could not remove $SUDOERS_DROPIN. Remove it by hand: sudo rm $SUDOERS_DROPIN"
    fi
}
trap revoke_privileges EXIT

##############################################
# Logging
##############################################
# Everything from here on is duplicated to a file. Without it, a failure scrolls
# away or vanishes with the session and there is nothing left to diagnose.

mkdir -p "$STATE_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

echo
info "First boot: applying Part 2 — $(date '+%Y-%m-%d %H:%M:%S')"
info "A copy of this run is kept at $LOG_FILE"

##############################################
# Pending work
##############################################
# The note is read here rather than inherited from the shell that invoked this
# script: it is the source of truth, and a variable set in a parent shell is not
# something to rely on.

MACHINE="$(sed -n 's/^MACHINE=//p' "$PENDING_FILE" | head -1)"
[[ -n "$MACHINE" ]] || die "The pending note carries no machine profile: $PENDING_FILE"

info "Machine profile: $MACHINE"

##############################################
# Network
##############################################
# Without a network there is nothing to do, and it is not a reason to burn the
# note: leaving it in place is what makes the next login retry on its own.

if ! ping -c1 -W3 archlinux.org >/dev/null 2>&1; then
    warn "No internet connection, so Part 2 cannot run yet."
    warn "Connect with:  nmtui"
    warn "Then log in again and this will pick up on its own."
    exit 1
fi

##############################################
# Part 2
##############################################

bash "$REPO_ROOT/dotfiles/bootstrap.sh" --machine "$MACHINE"

##############################################
# Done
##############################################
# The note goes only now, once everything above has succeeded. While it exists,
# both this provisional profile and the managed one keep retrying.

rm -f "$PENDING_FILE"

ok "Part 2 applied. This machine will not run the handover again."
info "Reboot to come up straight into the desktop."
