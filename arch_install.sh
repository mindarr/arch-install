#!/bin/bash

# Check for root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "You must run this script as root!"
    exit 1
fi

# ===== CONFIGURABLE VARIABLES =====
DISK="/dev/nvme1n1"                # Target disk for installation
USERNAME="ioan"                    # Default username
USER_PASSWORD="rockstar"           # Password for the user
ROOT_PASSWORD="rockstar"           # Password for root
HOSTNAME="archlinux"               # Hostname for the system
TIMEZONE="Europe/Rome"             # Timezone
LOCALE_LANG="en_GB.UTF-8"          # System language
LOCALE_GEN="en_GB.UTF-8 it_IT.UTF-8" # Locale to generate
KEYBOARD_LAYOUT="it"               # Keyboard layout

# ===== SCRIPT START =====

# Preparation
echo "Preparation: Ensure you are connected to the Internet."
read -p "Press Enter to continue..."

# Set keyboard layout
echo "Setting keyboard layout to $KEYBOARD_LAYOUT..."
loadkeys "$KEYBOARD_LAYOUT"

# Synchronize system clock
echo "Synchronizing system clock..."
timedatectl set-ntp true

# Partitioning and formatting with Btrfs
echo "Partitioning the disk..."
echo -e "g\nn\n\n\n+1G\nt\n1\nn\n\n\n\nw" | fdisk "$DISK"

echo "Formatting partitions..."
mkfs.fat -F32 "${DISK}p1"
mkfs.btrfs -f "${DISK}p2"

echo "Creating Btrfs subvolumes..."
mount "${DISK}p2" /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@opt
btrfs subvolume create /mnt/@var-cache
btrfs subvolume create /mnt/@var-crash
btrfs subvolume create /mnt/@var-AccountsService
btrfs subvolume create /mnt/@var-sddm
btrfs subvolume create /mnt/@var-libvirt-images
btrfs subvolume create /mnt/@var-log
btrfs subvolume create /mnt/@var-spool
btrfs subvolume create /mnt/@var-tmp
btrfs subvolume create /mnt/@var-www
btrfs subvolume create /mnt/@home-user-mozilla
umount /mnt

echo "Mounting Btrfs subvolumes..."
mount -o noatime,compress=zstd,subvol=@ "${DISK}p2" /mnt
mkdir -p /mnt/{boot/efi,home,opt,var/cache,var/crash,var/lib/AccountsService,var/lib/sddm,var/lib/libvirt/images,var/log,var/spool,var/tmp,var/www,home/$USERNAME/.mozilla}
mount -o noatime,compress=zstd,subvol=@home "${DISK}p2" /mnt/home
mount -o noatime,compress=zstd,subvol=@opt "${DISK}p2" /mnt/opt
mount -o noatime,compress=zstd,subvol=@var-cache "${DISK}p2" /mnt/var/cache
mount -o noatime,compress=zstd,subvol=@var-crash "${DISK}p2" /mnt/var/crash
mount -o noatime,compress=zstd,subvol=@var-AccountsService "${DISK}p2" /mnt/var/lib/AccountsService
mount -o noatime,compress=zstd,subvol=@var-sddm "${DISK}p2" /mnt/var/lib/sddm
mount -o noatime,compress=zstd,subvol=@var-libvirt-images "${DISK}p2" /mnt/var/lib/libvirt/images
mount -o noatime,compress=zstd,subvol=@var-log "${DISK}p2" /mnt/var/log
mount -o noatime,compress=zstd,subvol=@var-spool "${DISK}p2" /mnt/var/spool
mount -o noatime,compress=zstd,subvol=@var-tmp "${DISK}p2" /mnt/var/tmp
mount -o noatime,compress=zstd,subvol=@var-www "${DISK}p2" /mnt/var/www
mount -o noatime,compress=zstd,subvol=@home-user-mozilla "${DISK}p2" /mnt/home/$USERNAME/.mozilla

mount "${DISK}p1" /mnt/boot/efi

# Installing the base system
echo "Installing the base system..."
pacstrap /mnt base linux linux-firmware linux-lts linux-lts-headers linux-headers base-devel

# Generating fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
echo "Entering the new system..."
arch-chroot /mnt /bin/bash <<EOF

# Setting timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Configuring localization
echo "$LOCALE_GEN" | tr ' ' '
' | sed -i 's/^/#/g' /etc/locale.gen
locale-gen
echo "LANG=$LOCALE_LANG" > /etc/locale.conf
echo "KEYMAP=$KEYBOARD_LAYOUT" > /etc/vconsole.conf

# Configuring hostname
echo "$HOSTNAME" > /etc/hostname
cat <<HOSTS > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# Setting root password
echo "Setting root password..."
echo "root:$ROOT_PASSWORD" | chpasswd

# Creating user $USERNAME
echo "Creating user $USERNAME..."
useradd -m -G wheel $USERNAME
echo "$USERNAME:$USER_PASSWORD" | chpasswd
sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# Installing GRUB
echo "Installing GRUB..."
pacman -S --noconfirm grub efibootmgr os-prober dosfstools mtools
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Installing additional packages
echo "Installing additional packages..."
pacman -S --noconfirm networkmanager sddm plasma-meta konsole kwrite dolphin ark plasma-workspace egl-wayland partitionmanager kio-admin git nano firefox

# Installing video drivers
echo "Installing video drivers..."
pacman -S --noconfirm --needed mesa intel-media-driver mesa-vdpau

# Enabling services
systemctl enable NetworkManager
systemctl enable sddm

EOF

# Exit chroot and unmount
echo "Exiting chroot and unmounting partitions..."
umount -R /mnt

# Finish installation
echo "Installation complete! Rebooting..."
reboot
