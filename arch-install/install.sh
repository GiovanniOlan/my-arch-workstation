#!/usr/bin/env bash
#
# Optional preloaded answers, offered as the default of each prompt:
#
#   ARCH_INSTALL_DISK=/dev/vda
#   ARCH_INSTALL_HOSTNAME=archtest
#   ARCH_INSTALL_USERNAME=testuser
#   ARCH_INSTALL_USER_PASS=test
#   ARCH_INSTALL_LUKS_PASS=testtest
#   ARCH_INSTALL_SWAP_SIZE=1

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../lib/log.sh
source "$REPO_ROOT/lib/log.sh"

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

ask_secret() {
    local -n dest="$1"
    local prompt="$2" default="$3" env_name="$4"
    local first second

    while true; do
        if [[ -n "$default" ]]; then
            read -rsp "$prompt [Enter = use \$$env_name]: " first
            echo
            if [[ -z "$first" ]]; then
                dest="$default"
                return
            fi
        else
            read -rsp "$prompt: " first
            echo
            if [[ -z "$first" ]]; then
                warn "It cannot be empty."
                continue
            fi
        fi

        read -rsp "Confirm: " second
        echo
        if [[ "$first" == "$second" ]]; then
            break
        fi
        warn "They do not match, try again."
    done

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
# Preparation left to the user
##############################################

echo
warn "This script does NOT do the following — do it before continuing:"
warn "  Set the timezone:  timedatectl set-timezone Region/City"
warn "  Check the clock:   timedatectl status"
warn "  Set the keymap:    loadkeys <layout>   (e.g. loadkeys es, loadkeys us)"
echo
read -rp "Everything above is set. Continue? [y/N] " REPLY_CONTINUE
if [[ "${REPLY_CONTINUE,,}" != "y" ]]; then
    info "Aborted. Nothing was modified."
    exit 0
fi

##############################################
# Installation data
##############################################

echo
info "Available disks:"
lsblk -dpno NAME,SIZE,MODEL | grep -v "loop\|rom" || true
echo

ask DISK "Target disk (e.g. /dev/sda, /dev/nvme0n1)" "${ARCH_INSTALL_DISK:-}"
[[ -b "$DISK" ]] || die "Not a valid block device: $DISK"

ask HOST_NAME "Hostname" "${ARCH_INSTALL_HOSTNAME:-}"
[[ -n "$HOST_NAME" ]] || die "Hostname cannot be empty."

ask USERNAME "Username" "${ARCH_INSTALL_USERNAME:-}"
[[ -n "$USERNAME" ]] || die "Username cannot be empty."

ask_secret USER_PASS "Password for $USERNAME" \
    "${ARCH_INSTALL_USER_PASS:-}" ARCH_INSTALL_USER_PASS

ask_secret LUKS_PASS "LUKS passphrase" \
    "${ARCH_INSTALL_LUKS_PASS:-}" ARCH_INSTALL_LUKS_PASS

ask SWAP_SIZE "Swap size in GiB" "${ARCH_INSTALL_SWAP_SIZE:-4}"
[[ "$SWAP_SIZE" =~ ^[0-9]+$ ]] || die "Swap size must be a whole number of GiB: $SWAP_SIZE"
[[ "$SWAP_SIZE" -gt 0 ]] || die "Swap size must be greater than 0."

##############################################
# Destructive confirmation
##############################################

echo
warn "ALL data on $DISK will be destroyed."
warn "Disk: $DISK  |  Hostname: $HOST_NAME  |  User: $USERNAME  |  Swap: ${SWAP_SIZE}G"
echo
read -rp "Type YES to proceed: " REPLY_FINAL
if [[ "$REPLY_FINAL" != "YES" ]]; then
    info "Aborted. Nothing was modified."
    exit 0
fi

##############################################
# Environment auto-detection
##############################################

if grep -q GenuineIntel /proc/cpuinfo; then
    UCODE="intel-ucode"
elif grep -q AuthenticAMD /proc/cpuinfo; then
    UCODE="amd-ucode"
else
    UCODE=""
    warn "Unknown CPU vendor: no microcode package will be installed."
fi

TIMEZONE="$(timedatectl show --property=Timezone --value 2>/dev/null || true)"
if [[ -z "$TIMEZONE" ]]; then
    TIMEZONE="UTC"
    warn "Could not determine the timezone, falling back to $TIMEZONE."
fi

KEYMAP="$(localectl status 2>/dev/null | awk '/VC Keymap/{print $3}' || true)"
if [[ -z "$KEYMAP" || "$KEYMAP" == "(unset)" ]]; then
    KEYMAP="us"
    warn "Could not determine the keymap, falling back to $KEYMAP."
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
for subvol in @ @home @snapshots @var_log @var_cache_pacman_pkg @var_tmp @swap; do
    btrfs subvolume create "/mnt/$subvol"
done

umount /mnt

##############################################
# Mounting
##############################################

info "Mounting subvolumes..."

BTRFS_OPTS="noatime,compress=zstd,space_cache=v2"

mount -o "${BTRFS_OPTS},subvol=@" /dev/mapper/cryptroot /mnt

mkdir -p /mnt/{home,.snapshots,boot/efi,swap,var/log,var/cache/pacman/pkg,var/tmp}

mount -o "${BTRFS_OPTS},subvol=@home" /dev/mapper/cryptroot /mnt/home
mount -o "${BTRFS_OPTS},subvol=@snapshots" /dev/mapper/cryptroot /mnt/.snapshots
mount -o "${BTRFS_OPTS},subvol=@var_log" /dev/mapper/cryptroot /mnt/var/log
mount -o "${BTRFS_OPTS},subvol=@var_cache_pacman_pkg" /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o "${BTRFS_OPTS},subvol=@var_tmp" /dev/mapper/cryptroot /mnt/var/tmp
mount -o "${BTRFS_OPTS},subvol=@swap" /dev/mapper/cryptroot /mnt/swap

wipefs -a "$EFI_PART"
mkfs.fat -F32 -n EFI "$EFI_PART"
mount -t vfat "$EFI_PART" /mnt/boot/efi

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

ok "Swapfile active."

##############################################
# Base system
##############################################

info "Installing the base system (this takes a while)..."

PKGS=(
    base linux linux-headers linux-firmware
    btrfs-progs
    mkinitcpio
    grub efibootmgr
    snapper snap-pac grub-btrfs inotify-tools
    networkmanager
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

# initramfs: sd-encrypt opens the volume using the embedded keyfile
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf
sed -i 's|^FILES=.*|FILES=(/crypto_keyfile.bin)|' /etc/mkinitcpio.conf
mkinitcpio -P
chmod 600 /boot/initramfs-*.img

# User account. root stays locked: administration goes through privilege
# elevation. The password is set after this block on purpose: in here the text
# is re-parsed by the chroot shell, so a password with special characters would
# break or, worse, run.
useradd -m -G wheel,audio,video,storage "${USERNAME}"
passwd -l root
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL$/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# GRUB on an encrypted disk: it needs to read /boot, which lives in the volume
sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"rd.luks.name=${LUKS_UUID}=cryptroot rd.luks.key=/crypto_keyfile.bin root=/dev/mapper/cryptroot rootflags=subvol=@\"|" /etc/default/grub
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
# Teardown
##############################################

info "Unmounting..."
swapoff /mnt/swap/swapfile
umount -R /mnt
cryptsetup close cryptroot

echo
ok "Installation complete. Remove the installation media and reboot."
