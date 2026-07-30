#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../lib/log.sh
source "$REPO_ROOT/lib/log.sh"

CACHE_DIR="$SCRIPT_DIR/.cache"
STATE_DIR="$SCRIPT_DIR/.state"
mkdir -p "$CACHE_DIR" "$STATE_DIR"

ISO_BASE_URL="https://geo.mirror.pkgbuild.com/iso/latest"

STATE_DISK="$STATE_DIR/disk.qcow2"
DISK_SIZE="20G"

OVMF_CODE="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
OVMF_VARS_TEMPLATE="/usr/share/edk2/x64/OVMF_VARS.4m.fd"
# UEFI variables persist across runs: GRUB registers its boot entry there when
# it installs, and losing them would leave the installed system unbootable.
OVMF_VARS_RUN="$STATE_DIR/OVMF_VARS.fd"

REPO_MOUNT_TAG="repo"
REPO_MOUNT_POINT="/repo"

##############################################
# Run mode
##############################################
# Installing is the default: clean disk, boot from the ISO and console over
# serial, so text can be pasted and copied from the host terminal. With --boot
# the already installed system comes up instead, keeping disk and UEFI
# variables, on a graphical window: neither GRUB nor the target system speaks
# over the serial port.

BOOT_INSTALLED=false
case "${1:-}" in
    --boot) BOOT_INSTALLED=true ;;
    "") ;;
    *) die "Unknown option: ${1}. Usage: run.sh [--boot]" ;;
esac

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
require_tool bsdtar "install your distro's libarchive package"

ok "Required tools present."

[[ -f "$OVMF_CODE" && -f "$OVMF_VARS_TEMPLATE" ]] \
    || die "OVMF firmware not found at $OVMF_CODE. Install the edk2-ovmf package."

##############################################
# --boot mode: bring up the already installed system
##############################################
# It needs neither the ISO nor any download: just the disk and UEFI variables
# the installation left behind. It exits here so that the rest of the script
# stays a linear path dedicated to installing.

if $BOOT_INSTALLED; then
    [[ -f "$STATE_DISK" ]] \
        || die "No installed disk at $STATE_DISK. Run '$(basename "$0")' without --boot to install first."
    [[ -f "$OVMF_VARS_RUN" ]] \
        || die "No UEFI variables at $OVMF_VARS_RUN. Run '$(basename "$0")' without --boot to install first."

    info "Booting the installed system from $STATE_DISK..."
    warn "Graphical window: GRUB and the installed system do not use the serial console."

    exec qemu-system-x86_64 \
        -enable-kvm \
        -machine q35 \
        -m 4G \
        -smp 2 \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$OVMF_VARS_RUN" \
        -drive file="$STATE_DISK",if=virtio,format=qcow2 \
        -boot order=c \
        -netdev user,id=net0 -device virtio-net-pci,netdev=net0
fi

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
# ISO kernel, to boot over the serial console
##############################################
# The ISO boot menu does not speak over the serial port, so the kernel is
# booted directly with `console=ttyS0` appended. Archiso's own parameters are
# read from the ISO instead of being written by hand: they change with every
# release. Extraction happens only after the signature has been verified.

KERNEL_PATH="$CACHE_DIR/${ISO_NAME%.iso}-vmlinuz-linux"
INITRD_PATH="$CACHE_DIR/${ISO_NAME%.iso}-initramfs-linux.img"

extract_if_missing() {
    local member="$1" dest="$2"
    if [[ -f "$dest" ]]; then
        return
    fi
    info "Extracting $(basename "$member") from the ISO..."
    bsdtar -xOf "$ISO_PATH" "$member" >"$dest.tmp"
    mv "$dest.tmp" "$dest"
}

extract_if_missing "arch/boot/x86_64/vmlinuz-linux" "$KERNEL_PATH"
extract_if_missing "arch/boot/x86_64/initramfs-linux.img" "$INITRD_PATH"

ARCHISO_OPTIONS="$(bsdtar -xOf "$ISO_PATH" loader/entries/01-archiso-linux.conf \
    | sed -n 's/^options[[:space:]]*//p')"
[[ -n "$ARCHISO_OPTIONS" ]] || die "Could not read archiso's boot options from the ISO."

ok "Kernel and boot options ready."

##############################################
# Disposable state disk
##############################################

cp "$OVMF_VARS_TEMPLATE" "$OVMF_VARS_RUN"
rm -f "$STATE_DISK"
qemu-img create -f qcow2 "$STATE_DISK" "$DISK_SIZE" >/dev/null
ok "Disposable state disk created ($DISK_SIZE, at $STATE_DISK)."

##############################################
# Block to start a test install
##############################################
# The repository is shared with the VM over 9p (see the QEMU invocation), so
# the guest runs the working tree exactly as it stands on the host: no copying,
# no commit and no network needed. The values describe this very VM — the state
# disk is attached with `if=virtio`, so inside it shows up as /dev/vda — and
# they live here, not in the installer, which knows of no test environment.

VM_DISK="/dev/vda"
VM_HOSTNAME="archtest"
VM_USERNAME="testuser"
VM_USER_PASS="test"
VM_LUKS_PASS="testtest"
VM_SWAP_SIZE="1"

# The VM console takes over this very terminal, so its boot messages bury the
# block as soon as it starts. It is saved to a file and the user is given the
# chance to copy it before the terminal is handed over.
PASTE_FILE="$STATE_DIR/paste-inside-vm.sh"
cat >"$PASTE_FILE" <<EOF
mkdir -p $REPO_MOUNT_POINT && mount -t 9p -o trans=virtio,version=9p2000.L,ro $REPO_MOUNT_TAG $REPO_MOUNT_POINT
export ARCH_INSTALL_DISK=$VM_DISK
export ARCH_INSTALL_HOSTNAME=$VM_HOSTNAME
export ARCH_INSTALL_USERNAME=$VM_USERNAME
export ARCH_INSTALL_USER_PASS=$VM_USER_PASS
export ARCH_INSTALL_LUKS_PASS=$VM_LUKS_PASS
export ARCH_INSTALL_SWAP_SIZE=$VM_SWAP_SIZE
bash $REPO_MOUNT_POINT/arch-install/install.sh
EOF

info "Paste this inside the VM to start a test install:"
echo
cat "$PASTE_FILE"
echo
info "Saved at $PASTE_FILE, in case you need it again."
read -rp "Copy it now, then press Enter to boot the VM (its console takes over this terminal)... "
echo

##############################################
# Boot the VM
##############################################

info "Booting VM from $ISO_NAME. Its console is this terminal."
warn "To quit the VM: press Ctrl-A, release both, then press X."
echo

# The guest writes its console to the serial port and QEMU wires that port to
# this terminal, so copying and pasting are the terminal's usual ones.
qemu-system-x86_64 \
    -enable-kvm \
    -machine q35 \
    -m 4G \
    -smp 2 \
    -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
    -drive if=pflash,format=raw,file="$OVMF_VARS_RUN" \
    -drive file="$STATE_DISK",if=virtio,format=qcow2 \
    -cdrom "$ISO_PATH" \
    -kernel "$KERNEL_PATH" \
    -initrd "$INITRD_PATH" \
    -append "$ARCHISO_OPTIONS console=ttyS0,115200" \
    -display none \
    -serial mon:stdio \
    -netdev user,id=net0 -device virtio-net-pci,netdev=net0 \
    -virtfs "local,path=$REPO_ROOT,mount_tag=$REPO_MOUNT_TAG,security_model=mapped-xattr,readonly=on"
