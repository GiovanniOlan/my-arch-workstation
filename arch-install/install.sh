#!/usr/bin/env bash
#
# Part 1: turns a blank machine into a minimal, bootable Arch Linux install.
#
# Run it from the Arch ISO live environment, straight off the network:
#
#     bash <(curl -fsSL https://github.com/GiovanniOlan/my-arch-workstation/raw/main/arch-install/install.sh)
#
# Process substitution rather than `curl … | bash` on purpose. With a pipe the
# script itself arrives on stdin, so every prompt below would read the pipe
# instead of the keyboard and the password reads would hit end of file straight
# away. Written this way the script is a file descriptor and stdin stays the
# terminal.
#
# Nothing outside this file is needed to run it. That is why the message helpers
# are carried inline instead of sourced: on the live ISO there is no clone of the
# repository to source them from.
#
# Optional preloaded answers, offered as the default of each prompt:
#
#   ARCH_INSTALL_DISK=/dev/vda
#   ARCH_INSTALL_HOSTNAME=archtest
#   ARCH_INSTALL_USERNAME=testuser
#   ARCH_INSTALL_USER_PASS=test
#   ARCH_INSTALL_LUKS_PASS=testtest
#   ARCH_INSTALL_SWAP_SIZE=1
#   ARCH_INSTALL_KEYMAP=us
#   ARCH_INSTALL_TIMEZONE=America/Mexico_City
#   ARCH_INSTALL_MACHINE=laptop
#   ARCH_INSTALL_CHAIN=y
#
# And the repository the chained Part 2 clones, for forks and testing:
#
#   ARCH_INSTALL_REPO_URL=https://github.com/GiovanniOlan/my-arch-workstation.git

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

REPO_URL="${ARCH_INSTALL_REPO_URL:-https://github.com/GiovanniOlan/my-arch-workstation.git}"

ask() {
    local -n dest="$1"
    local prompt="$2" default="$3" reply

    if [[ -n "$default" ]]; then
        read -rp "$prompt [$default]: " reply
        dest="${reply:-$default}"
    else
        read -rp "$prompt: " reply
        dest="$reply"
    fi
}

MIN_SECRET_LENGTH=3

ask_secret() {
    local -n dest="$1"
    local prompt="$2" default="$3" env_name="$4"
    local first second

    while true; do
        if [[ -n "$default" ]]; then
            read -rsp "$prompt [Enter = use \$$env_name]: " first
            echo
            if [[ -z "$first" ]]; then
                first="$default"
                second="$default"
            else
                read -rsp "Confirm: " second
                echo
            fi
        else
            read -rsp "$prompt: " first
            echo
            if [[ -z "$first" ]]; then
                warn "It cannot be empty."
                continue
            fi
            read -rsp "Confirm: " second
            echo
        fi

        if [[ "$first" != "$second" ]]; then
            warn "They do not match, try again."
            continue
        fi
        if (( ${#first} < MIN_SECRET_LENGTH )); then
            warn "It must be at least $MIN_SECRET_LENGTH characters."
            continue
        fi
        break
    done

    # shellcheck disable=SC2034  # dest is a nameref: this writes the caller's variable
    dest="$first"
}

##############################################
# Execution environment checks
##############################################

[[ $EUID -eq 0 ]] || die "This script must be run as root."
[[ -d /run/archiso ]] || die "Not running from the Arch ISO live environment."
[[ -d /sys/firmware/efi ]] || die "UEFI not detected. Legacy BIOS is not supported."
ping -c1 -W3 archlinux.org &>/dev/null || die "No internet connection."

ok "Running as root from the Arch ISO."
ok "UEFI firmware detected."
ok "Internet connection verified."

##############################################
# Installation data
##############################################
# Every question is asked here, in one block, before anything is written. Past
# the destructive confirmation below, the installation runs to the end without
# asking for anything again.

# The keyboard layout goes first and is applied on the spot. The LUKS passphrase
# is typed with whatever layout is active at that moment, and a mismatch does not
# show up until the first boot, when the disk no longer opens and there is
# nothing left to do about it.
DETECTED_KEYMAP="$(localectl status 2>/dev/null | awk '/VC Keymap/{print $3}' || true)"
if [[ -z "$DETECTED_KEYMAP" || "$DETECTED_KEYMAP" == "(unset)" ]]; then
    DETECTED_KEYMAP="us"
fi

echo
ask KEYMAP "Keyboard layout (e.g. us, es, latam)" "${ARCH_INSTALL_KEYMAP:-$DETECTED_KEYMAP}"
loadkeys "$KEYMAP" 2>/dev/null \
    || die "Unknown keyboard layout: '$KEYMAP'. List them with: localectl list-keymaps"
ok "Layout '$KEYMAP' is now active: the passwords below are typed with it."

DETECTED_TIMEZONE="$(timedatectl show --property=Timezone --value 2>/dev/null || true)"
[[ -n "$DETECTED_TIMEZONE" ]] || DETECTED_TIMEZONE="UTC"

ask TIMEZONE "Timezone (Region/City)" "${ARCH_INSTALL_TIMEZONE:-$DETECTED_TIMEZONE}"
[[ -f "/usr/share/zoneinfo/$TIMEZONE" ]] \
    || die "Unknown timezone: '$TIMEZONE'. List them with: timedatectl list-timezones"
timedatectl set-timezone "$TIMEZONE" 2>/dev/null || true

echo
info "Available disks:"
lsblk -dpno NAME,SIZE,MODEL | grep -v "loop\|rom" || true
echo

ask DISK "Target disk (e.g. /dev/sda, /dev/nvme0n1)" "${ARCH_INSTALL_DISK:-}"
[[ -b "$DISK" ]] || die "Not a valid block device: $DISK"

ask HOST_NAME "Hostname" "${ARCH_INSTALL_HOSTNAME:-}"
[[ "$HOST_NAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$ ]] \
    || die "Invalid hostname: '$HOST_NAME'. Use letters, digits and hyphens, not starting or ending with a hyphen."

ask USERNAME "Username" "${ARCH_INSTALL_USERNAME:-}"
[[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] \
    || die "Invalid username: '$USERNAME'. Use lowercase letters, digits, underscore and hyphen, starting with a letter or underscore."

ask_secret USER_PASS "Password for $USERNAME" \
    "${ARCH_INSTALL_USER_PASS:-}" ARCH_INSTALL_USER_PASS

ask_secret LUKS_PASS "LUKS passphrase" \
    "${ARCH_INSTALL_LUKS_PASS:-}" ARCH_INSTALL_LUKS_PASS

RAM_GIB=$(( ( $(awk '/^MemTotal:/{print $2}' /proc/meminfo) + 1048575 ) / 1048576 ))

ask SWAP_SIZE "Swap size in GiB" "${ARCH_INSTALL_SWAP_SIZE:-$RAM_GIB}"
[[ "$SWAP_SIZE" =~ ^[0-9]+$ ]] || die "Swap size must be a whole number of GiB: $SWAP_SIZE"
[[ "$SWAP_SIZE" -gt 0 ]] || die "Swap size must be greater than 0."
if [[ "$SWAP_SIZE" -lt "$RAM_GIB" ]]; then
    warn "Swap (${SWAP_SIZE}G) is smaller than RAM (${RAM_GIB}G): hibernation will not work."
fi

# Part 2 is not this script's job, but the questions it needs are asked here so
# that the first boot has nothing left to ask. The machine profile is only worth
# collecting when it is going to be handed over, so it hangs off the answer above.
echo
ask CHAIN_REPLY "Apply the dotfiles automatically on the first boot? (y/n)" "${ARCH_INSTALL_CHAIN:-y}"
case "${CHAIN_REPLY,,}" in
    y | yes) CHAIN_DOTFILES=true ;;
    n | no) CHAIN_DOTFILES=false ;;
    *) die "Answer 'y' or 'n', not '$CHAIN_REPLY'." ;;
esac

MACHINE=""
if $CHAIN_DOTFILES; then
    ask MACHINE "Machine profile (desktop/laptop)" "${ARCH_INSTALL_MACHINE:-}"
    [[ "$MACHINE" == "desktop" || "$MACHINE" == "laptop" ]] \
        || die "Invalid machine profile: '$MACHINE'. Use 'desktop' or 'laptop'."
fi

##############################################
# Destructive confirmation
##############################################

echo
warn "ALL data on $DISK will be destroyed."
warn "Disk: $DISK  |  Hostname: $HOST_NAME  |  User: $USERNAME  |  Swap: ${SWAP_SIZE}G"
if $CHAIN_DOTFILES; then
    warn "Dotfiles: applied on the first boot, profile '$MACHINE'."
else
    warn "Dotfiles: not applied. The first boot is a plain text session."
fi
echo
read -rp "Type YES to proceed: " REPLY_FINAL
if [[ "$REPLY_FINAL" != "YES" ]]; then
    info "Aborted. Nothing was modified."
    exit 0
fi

##############################################
# Environment auto-detection
##############################################
# What is left here is what the user is never asked about. The timezone and the
# keyboard layout used to be detected in this block too; they are now questions
# of their own, and what is detected serves as their default answer.

if grep -q GenuineIntel /proc/cpuinfo; then
    UCODE="intel-ucode"
elif grep -q AuthenticAMD /proc/cpuinfo; then
    UCODE="amd-ucode"
else
    UCODE=""
    warn "Unknown CPU vendor: no microcode package will be installed."
fi

##############################################
# Leftovers from an interrupted previous run
##############################################
# Their absence is not an error: on a clean run there is nothing to release.

swapoff /mnt/swap/swapfile 2>/dev/null || true
umount -R /mnt 2>/dev/null || true
cryptsetup close cryptroot 2>/dev/null || true

##############################################
# Partitioning
##############################################

info "Discarding previous contents of $DISK..."
if blkdiscard -f "$DISK" 2>/dev/null; then
    ok "Previous contents discarded."
else
    warn "This device does not support discarding: previous contents are left in place."
fi

info "Partitioning $DISK..."

sgdisk --zap-all "$DISK"
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:"EFI" "$DISK"
sgdisk -n 2:0:0 -t 2:8300 -c 2:"LUKS" "$DISK"
partprobe "$DISK"
udevadm settle

if [[ "$DISK" =~ (nvme|mmcblk) ]]; then
    EFI_PART="${DISK}p1"
    LUKS_PART="${DISK}p2"
else
    EFI_PART="${DISK}1"
    LUKS_PART="${DISK}2"
fi

ok "Partitioned: $EFI_PART (EFI), $LUKS_PART (LUKS)."

##############################################
# LUKS2
##############################################

info "Setting up LUKS2 on $LUKS_PART..."

wipefs -a "$LUKS_PART"

# shellcheck disable=SC2153  # LUKS_PASS is set by ask_secret through a nameref
printf '%s' "$LUKS_PASS" | cryptsetup luksFormat --batch-mode --type luks2 "$LUKS_PART" -
printf '%s' "$LUKS_PASS" | cryptsetup open "$LUKS_PART" cryptroot -

dd bs=512 count=4 if=/dev/urandom of=/tmp/crypto_keyfile.bin status=none
chmod 600 /tmp/crypto_keyfile.bin
printf '%s' "$LUKS_PASS" | cryptsetup luksAddKey "$LUKS_PART" /tmp/crypto_keyfile.bin -

unset LUKS_PASS ARCH_INSTALL_LUKS_PASS

ok "Encrypted volume open at /dev/mapper/cryptroot."

##############################################
# BTRFS and subvolumes
##############################################

info "Creating the BTRFS filesystem..."
mkfs.btrfs -L archlinux /dev/mapper/cryptroot
mount /dev/mapper/cryptroot /mnt

info "Creating subvolumes..."
for subvol in @ @home @snapshots @var_log @var_cache_pacman_pkg @var_tmp \
    @var_lib_docker @swap; do
    btrfs subvolume create "/mnt/$subvol"
done

umount /mnt

##############################################
# Mounting
##############################################

info "Mounting subvolumes..."

BTRFS_OPTS="noatime,compress=zstd,space_cache=v2"
SWAP_OPTS="noatime,space_cache=v2"

mount -o "${BTRFS_OPTS},subvol=@" /dev/mapper/cryptroot /mnt

mkdir -p /mnt/{home,.snapshots,boot/efi,swap,var/log,var/cache/pacman/pkg,var/tmp,var/lib/docker}

mount -o "${BTRFS_OPTS},subvol=@home" /dev/mapper/cryptroot /mnt/home
mount -o "${BTRFS_OPTS},subvol=@snapshots" /dev/mapper/cryptroot /mnt/.snapshots
mount -o "${BTRFS_OPTS},subvol=@var_log" /dev/mapper/cryptroot /mnt/var/log
mount -o "${BTRFS_OPTS},subvol=@var_cache_pacman_pkg" /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o "${BTRFS_OPTS},subvol=@var_tmp" /dev/mapper/cryptroot /mnt/var/tmp
mount -o "${BTRFS_OPTS},subvol=@var_lib_docker" /dev/mapper/cryptroot /mnt/var/lib/docker
mount -o "${SWAP_OPTS},subvol=@swap" /dev/mapper/cryptroot /mnt/swap

wipefs -a "$EFI_PART"
mkfs.fat -F32 -n EFI "$EFI_PART"
mount -t vfat -o fmask=0077,dmask=0077 "$EFI_PART" /mnt/boot/efi

ok "Filesystems mounted."

install -m600 /tmp/crypto_keyfile.bin /mnt/crypto_keyfile.bin
rm -f /tmp/crypto_keyfile.bin

##############################################
# Swapfile
##############################################

info "Creating the ${SWAP_SIZE}G swapfile..."

# BTRFS does not accept swapfiles with copy-on-write enabled.
chattr +C /mnt/swap
truncate -s 0 /mnt/swap/swapfile
chattr +C /mnt/swap/swapfile
dd if=/dev/zero of=/mnt/swap/swapfile bs=1M count=$((SWAP_SIZE * 1024)) status=progress
chmod 600 /mnt/swap/swapfile
mkswap /mnt/swap/swapfile
swapon /mnt/swap/swapfile

SWAP_OFFSET="$(btrfs inspect-internal map-swapfile -r /mnt/swap/swapfile 2>/dev/null || true)"
if [[ -n "$SWAP_OFFSET" ]]; then
    RESUME_CMDLINE=" resume=/dev/mapper/cryptroot resume_offset=${SWAP_OFFSET}"
    ok "Swapfile active (hibernation offset ${SWAP_OFFSET})."
else
    RESUME_CMDLINE=""
    warn "Could not read the swapfile offset: hibernation will not be configured."
fi

##############################################
# Base system
##############################################

info "Installing the base system (this takes a while)..."

PKGS=(
    base linux linux-headers linux-firmware
    linux-lts linux-lts-headers
    btrfs-progs
    mkinitcpio
    grub efibootmgr
    snapper snap-pac grub-btrfs inotify-tools
    networkmanager
    chrony
    firewalld
    sudo git base-devel
    neovim
)
if [[ -n "$UCODE" ]]; then
    PKGS+=("$UCODE")
fi

pacstrap -K /mnt "${PKGS[@]}"

info "Generating fstab..."
genfstab -U /mnt >>/mnt/etc/fstab

##############################################
# Installed system configuration
##############################################

LUKS_UUID="$(blkid -s UUID -o value "$LUKS_PART")"

info "Configuring the installed system..."

arch-chroot /mnt /bin/bash <<CHROOT
set -euo pipefail

# Timezone and clock
ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
hwclock --systohc

# Locales: English interface, Mexican regional formats
sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' /etc/locale.gen
sed -i 's/^#\(es_MX.UTF-8 UTF-8\)/\1/' /etc/locale.gen
locale-gen
cat > /etc/locale.conf <<'EOF'
LANG=en_US.UTF-8
LC_TIME=es_MX.UTF-8
LC_MONETARY=es_MX.UTF-8
LC_PAPER=es_MX.UTF-8
LC_MEASUREMENT=es_MX.UTF-8
LC_NUMERIC=es_MX.UTF-8
LC_ADDRESS=es_MX.UTF-8
LC_TELEPHONE=es_MX.UTF-8
LC_NAME=es_MX.UTF-8
EOF

# Console keymap
echo "KEYMAP=${KEYMAP}" > /etc/vconsole.conf

# Network identity
echo "${HOST_NAME}" > /etc/hostname
printf '127.0.0.1\tlocalhost\n::1\t\tlocalhost\n127.0.1.1\t${HOST_NAME}.localdomain ${HOST_NAME}\n' > /etc/hosts

sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf
sed -i 's|^FILES=.*|FILES=(/crypto_keyfile.bin)|' /etc/mkinitcpio.conf
mkinitcpio -P

# User account. root stays locked: administration goes through privilege
# elevation. The password is set after this block on purpose: in here the text
# is re-parsed by the chroot shell, so a password with special characters would
# break or, worse, run.
useradd -m -G wheel,audio,video,storage "${USERNAME}"
passwd -l root

# A drop-in rather than an edit of /etc/sudoers: uncommenting a line with sed
# depends on an upstream comment staying byte for byte the same, and sed reports
# success even when it matches nothing. With root locked, a silent miss there
# leaves a machine with no way in at all. visudo -c makes a mistake fatal here,
# under set -e, instead of at first boot.
printf '%%wheel ALL=(ALL:ALL) ALL\n' > /etc/sudoers.d/10-wheel
chmod 440 /etc/sudoers.d/10-wheel
visudo -cf /etc/sudoers.d/10-wheel

# GRUB on an encrypted disk: it needs to read /boot, which lives in the volume.
# rd.luks.options=discard lets TRIM through to the SSD, which LUKS blocks by
# default. It leaks which blocks are in use — not their contents — in exchange
# for the drive not degrading as it fills up.
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"rd.luks.name=${LUKS_UUID}=cryptroot rd.luks.key=/crypto_keyfile.bin rd.luks.options=${LUKS_UUID}=discard root=/dev/mapper/cryptroot rootflags=subvol=@${RESUME_CMDLINE}\"|" /etc/default/grub
sed -i 's/^#GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB

# Snapshots. /.snapshots already holds the dedicated subvolume, but snapper
# insists on creating its own while generating the config: let it, throw that
# one away and put back ours, which does survive a rollback of the root.
umount /.snapshots
rmdir /.snapshots
snapper --no-dbus -c root create-config /
btrfs subvolume delete /.snapshots
mkdir /.snapshots
mount /.snapshots
chmod 750 /.snapshots

# Protection comes from snap-pac on every pacman transaction, not from a timer.
sed -i 's/^TIMELINE_CREATE=.*/TIMELINE_CREATE="no"/' /etc/snapper/configs/root
sed -i 's/^NUMBER_LIMIT=.*/NUMBER_LIMIT="20"/' /etc/snapper/configs/root
sed -i 's/^NUMBER_LIMIT_IMPORTANT=.*/NUMBER_LIMIT_IMPORTANT="10"/' /etc/snapper/configs/root
sed -i "s/^ALLOW_USERS=.*/ALLOW_USERS=\"${USERNAME}\"/" /etc/snapper/configs/root

# The packaged service points at timeshift; this setup uses snapper.
mkdir -p /etc/systemd/system/grub-btrfsd.service.d
cat > /etc/systemd/system/grub-btrfsd.service.d/override.conf <<'EOF'
[Service]
ExecStart=
ExecStart=/usr/bin/grub-btrfsd --syslog /.snapshots
EOF

systemctl enable NetworkManager
systemctl enable chronyd.service
systemctl disable systemd-timesyncd.service || true
systemctl enable firewalld.service
systemctl enable fstrim.timer
systemctl enable grub-btrfsd.service
systemctl enable snapper-cleanup.timer

# The initial snapshot must exist before the menu is generated, to show up in it.
snapper --no-dbus -c root create -d "Initial installation"
grub-mkconfig -o /boot/grub/grub.cfg
CHROOT

printf '%s:%s' "$USERNAME" "$USER_PASS" | arch-chroot /mnt chpasswd

unset USER_PASS ARCH_INSTALL_USER_PASS

ok "System configured."

##############################################
# Wireless credentials handover
##############################################
# The live ISO connects with iwd; the installed system uses NetworkManager. They
# keep their networks in different formats, so this is a translation rather than a
# copy — and it means the passphrase is not typed a second time. Without it, a
# machine installed over WiFi reaches its first boot with no way onto the network,
# which is precisely when the chained Part 2 needs one.
#
# Independent of the chaining answer: a machine that cannot reach the network on
# its own is a nuisance either way.

IWD_DIR="/var/lib/iwd"
NM_DIR="/mnt/etc/NetworkManager/system-connections"

# Most recently written wins: in a live session that is the network the
# installation itself is running over.
WIFI_PSK_FILE=""
if [[ -d "$IWD_DIR" ]]; then
    WIFI_PSK_FILE="$(find "$IWD_DIR" -maxdepth 1 -name '*.psk' -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -1 | cut -d' ' -f2-)"
fi

if [[ -z "$WIFI_PSK_FILE" ]]; then
    info "No saved wireless network in the live environment: nothing to carry over."
else
    WIFI_SSID="$(basename "$WIFI_PSK_FILE" .psk)"
    # iwd hex-encodes names it cannot store verbatim, prefixed with '='. Decoding
    # them is not worth it here: nmtui after the first boot is the way out.
    if [[ "$WIFI_SSID" == =* ]]; then
        warn "Wireless network with a non-printable name: not carried over. Use nmtui after the first boot."
    else
        # NetworkManager takes either the passphrase or the 64-hex pre-shared key
        # in the same field, so whichever iwd stored is good enough.
        WIFI_SECRET="$(sed -n 's/^Passphrase=//p' "$WIFI_PSK_FILE" | head -1)"
        [[ -n "$WIFI_SECRET" ]] \
            || WIFI_SECRET="$(sed -n 's/^PreSharedKey=//p' "$WIFI_PSK_FILE" | head -1)"

        if [[ -z "$WIFI_SECRET" ]]; then
            warn "Saved network '$WIFI_SSID' holds no usable secret: not carried over."
        else
            mkdir -p "$NM_DIR"
            # Created restricted and only then filled in: NetworkManager refuses to
            # read a connection file that others can read, and writing first would
            # leave the secret world-readable in between.
            install -m600 /dev/null "$NM_DIR/$WIFI_SSID.nmconnection"
            cat >"$NM_DIR/$WIFI_SSID.nmconnection" <<EOF
[connection]
id=$WIFI_SSID
uuid=$(cat /proc/sys/kernel/random/uuid)
type=wifi
autoconnect=true

[wifi]
mode=infrastructure
ssid=$WIFI_SSID

[wifi-security]
key-mgmt=wpa-psk
psk=$WIFI_SECRET

[ipv4]
method=auto

[ipv6]
method=auto
EOF
            unset WIFI_SECRET
            ok "Wireless network '$WIFI_SSID' carried over to the installed system."
        fi
    fi
fi

##############################################
# Chaining Part 2 into the first boot
##############################################
# Nothing of Part 2 runs here. What gets seeded is a note saying there is work
# pending, a shell profile that acts on it, and a temporary privilege grant so
# that first attempt needs nobody in front of the screen.
#
# The clone happens on the first boot rather than now, on purpose: git is already
# installed there as part of the base system, the machine is the real one, and
# this script stays ignorant of dotfiles beyond a URL.

if $CHAIN_DOTFILES; then
    info "Seeding the first-boot handover..."

    USER_HOME="/mnt/home/$USERNAME"

    mkdir -p "$USER_HOME/.local/state"
    cat >"$USER_HOME/.local/state/first-boot-pending" <<EOF
# Written by the Arch installer. Its presence is what marks Part 2 as pending;
# it is removed once the dotfiles have been applied successfully.
REPO_URL=$REPO_URL
MACHINE=$MACHINE
EOF

    # Provisional profile: it only covers the gap until chezmoi writes the managed
    # one, which carries the same check so that a failed run still retries.
    cat >"$USER_HOME/.bash_profile" <<'PROFILE'
#
# ~/.bash_profile — written by the Arch installer, replaced by the managed one
# as soon as the dotfiles are applied.
#

[[ -f ~/.bashrc ]] && . ~/.bashrc

if [ -f "$HOME/.local/state/first-boot-pending" ] && [ "$XDG_VTNR" = "1" ]; then
    . "$HOME/.local/state/first-boot-pending"
    _repo_dir="$HOME/workspaces/$(basename "$REPO_URL" .git)"
    if [ -d "$_repo_dir/.git" ] || git clone "$REPO_URL" "$_repo_dir"; then
        bash "$_repo_dir/arch-install/first-boot.sh"
    else
        echo "Could not clone $REPO_URL. Check the network and log in again." >&2
    fi
    unset _repo_dir
fi

# Only once nothing is pending: a failed run leaves the note in place and drops
# to a text shell, where the error is still on screen.
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = "1" ] \
    && [ ! -f "$HOME/.local/state/first-boot-pending" ] \
    && command -v start-hyprland >/dev/null 2>&1; then
    exec start-hyprland
fi
PROFILE

    arch-chroot /mnt chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.local" "/home/$USERNAME/.bash_profile"

    # One-shot privilege grant. first-boot.sh revokes it when it exits, however it
    # exits, so a failed run does not leave it behind.
    printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$USERNAME" >/mnt/etc/sudoers.d/99-first-boot
    chmod 440 /mnt/etc/sudoers.d/99-first-boot
    arch-chroot /mnt visudo -cf /etc/sudoers.d/99-first-boot >/dev/null

    ok "First boot will apply the dotfiles by itself (profile '$MACHINE')."
fi

##############################################
# Teardown
##############################################

info "Unmounting..."
swapoff /mnt/swap/swapfile
umount -R /mnt
cryptsetup close cryptroot

echo
ok "Installation complete. Remove the installation media and reboot."
if $CHAIN_DOTFILES; then
    info "On the first login the dotfiles will be applied on their own: packages,"
    info "services and desktop. It takes a while and needs no input."
else
    info "The system boots as a minimal install. To apply the dotfiles later, see"
    info "the Part 2 entry point in the README."
fi
