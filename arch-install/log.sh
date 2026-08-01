#!/usr/bin/env bash
# shellcheck shell=bash
#
# Message helpers for the scripts of Part 1 that always run from a clone:
# first-boot.sh and the development tooling under dev/.
#
# The entry points of the project (install.sh here, dotfiles/bootstrap.sh) do not
# load this file — they carry their own copy of these helpers, because they have
# to run on a machine that does not have the repository yet, fetched straight off
# the network, and there is nothing there to source.
#
# This is a library: load it with `source`, do not execute it. Each script
# locates it from its own path, never from the working directory:
#
#     SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#     source "$SCRIPT_DIR/log.sh"

# Running it directly does nothing useful and usually means a caller mistake.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "log.sh is a library: source it, don't execute it." >&2
    exit 1
fi

# Where the library itself lives, so that whatever sits next to it can be found
# without depending on who loaded it.
# shellcheck disable=SC2034  # consumed by other scripts, not by this file
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

# Progress: what is being done right now.
info() { echo -e "${BOLD}:: $*${RESET}"; }

# Confirmation: something finished successfully.
ok() { echo -e "${GREEN}[✓] $*${RESET}"; }

# Warning: something the user should notice, without stopping the flow.
warn() { echo -e "${YELLOW}[!] $*${RESET}"; }

# Fatal error: to stderr and with a non-zero exit status.
die() {
    echo -e "${RED}[✗] $*${RESET}" >&2
    exit 1
}
