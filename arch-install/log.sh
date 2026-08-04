#!/usr/bin/env bash
# shellcheck shell=bash

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "log.sh is a library: source it, don't execute it." >&2
    exit 1
fi

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
