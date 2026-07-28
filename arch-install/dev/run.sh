#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
RESET='\033[0m'

info() { echo -e "${BOLD}:: $*${RESET}"; }
ok()   { echo -e "${GREEN}[OK] $*${RESET}"; }
die()  { echo -e "${RED}[ERROR] $*${RESET}" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/.cache"
STATE_DIR="$SCRIPT_DIR/.state"
mkdir -p "$CACHE_DIR" "$STATE_DIR"

ISO_BASE_URL="https://geo.mirror.pkgbuild.com/iso/latest"

##############################################
# Preflight: required tools
##############################################

require_tool() {
    local tool="$1" hint="$2"
    command -v "$tool" >/dev/null 2>&1 || die "Missing '$tool'. Install it with: $hint"
}

require_tool qemu-system-x86_64 "install your distro's qemu package (on Arch: pacman -S qemu-desktop)"
require_tool curl "install your distro's curl package"
require_tool gpg "install your distro's gnupg package"

ok "Required tools present."

##############################################
# Official ISO download and caching
##############################################

fetch_current_iso_name() {
    curl -fsSL "$ISO_BASE_URL/sha256sums.txt" | awk '/x86_64\.iso$/ {print $2; exit}'
}

ISO_NAME="$(fetch_current_iso_name)"
[[ -n "$ISO_NAME" ]] || die "Could not determine the current official ISO name from $ISO_BASE_URL/sha256sums.txt"

ISO_PATH="$CACHE_DIR/$ISO_NAME"
SIG_PATH="$ISO_PATH.sig"

download_if_missing() {
    local url="$1" dest="$2"
    if [[ -f "$dest" ]]; then
        ok "Already cached: $(basename "$dest")"
        return
    fi
    info "Downloading $(basename "$dest")..."
    curl -fL --output "$dest.tmp" "$url"
    mv "$dest.tmp" "$dest"
    ok "Downloaded: $(basename "$dest")"
}

download_if_missing "$ISO_BASE_URL/$ISO_NAME"     "$ISO_PATH"
download_if_missing "$ISO_BASE_URL/$ISO_NAME.sig" "$SIG_PATH"

##############################################
# Authenticity verification (GPG + WKD)
##############################################
# Fingerprint of Arch's release signing key (Pierre Schmitz), as documented
# at https://archlinux.org/download/ and confirmed as a current master key
# at https://archlinux.org/master-keys/. If Arch rotates this key, this
# value has to be updated by hand.
ARCH_RELEASE_KEY_EMAIL="pierre@archlinux.org"
ARCH_RELEASE_KEY_FPR="3E80CA1A8B89F69CBA57D98A76A5EF9054449A5C"

verify_iso_signature() {
    local gnupg_home status signed_fpr
    gnupg_home="$(mktemp -d "$STATE_DIR/gnupg.XXXXXX")"
    chmod 700 "$gnupg_home"

    info "Fetching Arch's official key via WKD ($ARCH_RELEASE_KEY_EMAIL)..."
    if ! GNUPGHOME="$gnupg_home" gpg --batch --auto-key-locate wkd \
            --locate-external-key "$ARCH_RELEASE_KEY_EMAIL" >/dev/null 2>&1; then
        rm -rf "$gnupg_home"
        die "Could not fetch Arch's official key via WKD. Check your network connection."
    fi

    info "Verifying ISO signature..."
    if ! status="$(GNUPGHOME="$gnupg_home" gpg --batch --status-fd 1 \
            --verify "$SIG_PATH" "$ISO_PATH" 2>/dev/null)"; then
        rm -rf "$gnupg_home"
        die "The ISO signature is not valid. Refusing to boot the VM."
    fi
    rm -rf "$gnupg_home"

    signed_fpr="$(awk '/^\[GNUPG:\] VALIDSIG/ {print $3; exit}' <<<"$status")"
    if [[ "$signed_fpr" != "$ARCH_RELEASE_KEY_FPR" ]]; then
        die "The ISO is signed by an unexpected key (got: ${signed_fpr:-none}, expected: $ARCH_RELEASE_KEY_FPR). Refusing to boot the VM."
    fi

    ok "Signature verified: the ISO was signed by Arch's official key."
}

verify_iso_signature

##############################################
# Boot the VM
##############################################

OVMF_CODE="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
OVMF_VARS_TEMPLATE="/usr/share/edk2/x64/OVMF_VARS.4m.fd"
[[ -f "$OVMF_CODE" && -f "$OVMF_VARS_TEMPLATE" ]] \
    || die "OVMF firmware not found at $OVMF_CODE. Install the edk2-ovmf package."

OVMF_VARS_RUN="$STATE_DIR/OVMF_VARS.fd"
cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS_RUN"

STATE_DISK="$STATE_DIR/disk.qcow2"
DISK_SIZE="20G"
rm -f "$STATE_DISK"
qemu-img create -f qcow2 "$STATE_DISK" "$DISK_SIZE" >/dev/null
ok "Disposable state disk created ($DISK_SIZE, at $STATE_DISK)."

info "Booting VM from $ISO_NAME..."
qemu-system-x86_64 \
    -enable-kvm \
    -machine q35 \
    -m 4G \
    -smp 2 \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$OVMF_VARS_RUN" \
    -drive file="$STATE_DISK",if=virtio,format=qcow2 \
    -cdrom "$ISO_PATH" \
    -boot order=d \
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0
