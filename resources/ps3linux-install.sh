#!/bin/bash

set -eo pipefail

# Variables
BOOT_DEV=""
ROOT_PART=""
SWAP_PART=""
HOST_NAME="localhost"

# Check if we have root privileges
if [ $(id -u) -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Usage message
usage() {
    cat << EOF

Usage: $0 <OPTIONS>

OPTIONS:
  --boot <DEVICE>       PS3's hard disk device (HDD) name (as seen by petitboot)
                        use /dev/ps3da if PS3 is downgraded (on Firmware <= 3.15)
                        use /dev/ps3dd if PS3 is on CFW like Rebug or Evilnat

  --root <PARTITION>    HDD partition number where PS3 LINUX will be installed

  --swap <PARTITION>    HDD partition number to be used as system swap device

  --hostname <HOSTNAME> Hostname for the PS3LINUX system

  --help                show this help

EXAMPLE: ps3linux-install.sh --boot /dev/ps3da --root 2 --swap 1 --hostname localhost

NOTE: This script should only be run after your PS3's HDD has been partitioned
      and contains at least one root partition and one swap partition. You can
      partition the drive by running fdisk /dev/ps3dd from the command line.
    
Suggested layout: Name          Type         Size
                  /dev/ps3dd1   Linux Swap   2 GiB (2048 MiB)
                  /dev/ps3dd2   Linux        remainder of drive

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --boot)
            BOOT_DEV="$2"
            shift 2
            ;;
        --root)
            ROOT_PART="$2"
            shift 2
            ;;
        --swap)
            SWAP_PART="$2"
            shift 2
            ;;
        --hostname)
            HOST_NAME="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

# Make sure all necessary variables are not empty
if [ -z $BOOT_DEV ]; then
	echo "Error: No boot device provided."
	usage
	exit 1
fi
if [ -z $ROOT_PART ]; then
	echo "Error: No root partition provided."
	usage
	exit 1
fi
if [ -z $SWAP_PART ]; then
	echo "Error: No swap partition provided."
	usage
	exit 1
fi

# Make sure user provided block devices exist
if [ ! -b /dev/ps3dd ]; then
	echo "Error: Could not find HDD device /dev/ps3dd."
	exit 1
fi
if [ ! -b /dev/ps3dd$ROOT_PART ]; then
	echo "Error: Could not find root partition /dev/ps3dd$ROOT_PART. You must partition your PS3 HDD's Linux region before running this script."
	exit 1
fi
if [ ! -b /dev/ps3dd$SWAP_PART ]; then
	echo "Error: Could not find swap partition /dev/ps3dd$SWAP_PART. You must partition your PS3 HDD's Linux region before running this script."
	exit 1
fi

# Activate HDD swap partition
mkswap /dev/ps3dd$SWAP_PART
swapon -p 50 /dev/ps3dd$SWAP_PART

# Format and mount target root partition
mkfs -t ext4 /dev/ps3dd$ROOT_PART
mount -t ext4 /dev/ps3dd$ROOT_PART /mnt/target
rm -rf /mnt/target/*

echo "Building dnf metadata cache. This can take several minutes..."
echo ""

# Install root file system
dnf -y --releasever=28 --forcearch=ppc64 --disablerepo=* --enablerepo=fedora --repofrompath=ps3linux,https://ps3linux.net/ps3linux-repos/1/ppc64/ --installroot=/mnt/target --exclude=fedora-release,generic-release --nogpgcheck install filesystem ps3linux-release

# Mount virtual file systems
rm -f /mnt/target/dev/null
mknod -m 600 /mnt/target/dev/console c 5 1
mknod -m 666 /mnt/target/dev/null c 1 3
mount -t proc /proc /mnt/target/proc
mount -t sysfs /sys /mnt/target/sys
mount -o bind /dev /mnt/target/dev
mount -o bind /dev/pts /mnt/target/dev/pts
mount -t tmpfs tmpfs /mnt/target/run
mount -t tmpfs tmpfs /mnt/target/tmp

# Create fstab and enable network in chroot
cat > /mnt/target/etc/fstab << EOF
/dev/ps3dd$ROOT_PART / ext4 noatime 0 1
/dev/ps3dd$SWAP_PART none swap pri=1 0 0
spufs /spu spufs defaults 0 0
EOF
echo "nameserver 8.8.8.8" > /mnt/target/etc/resolv.conf

# Install core package group
dnf -y --releasever=1 --forcearch=ppc64 --disablerepo=* --enablerepo=fedora --enablerepo=ps3linux --installroot=/mnt/target --nogpgcheck groupinstall core

# Prepare bootloader config file
cat > /mnt/target/etc/yaboot.conf << EOF
boot=$BOOT_DEV
partition=$ROOT_PART
EOF

# Install kernel and additional packages and clear dnf cache
dnf -y --releasever=1 --forcearch=ppc64 --disablerepo=* --enablerepo=fedora --enablerepo=ps3linux --installroot=/mnt/target --nogpgcheck install kernel kernel-core kernel-modules kernel-headers bash-completion nfs-utils wpa_supplicant dosfstools vim nano
dnf --installroot=/mnt/target clean all

# Complete bootloader config file yaboot.conf
sed -i "s|append=\"\"|append=\"video=ps3fb:mode:1669 root=/dev/ps3dd$ROOT_PART selinux=0 audit=0\"|" /mnt/target/etc/yaboot.conf

# Set hostname
echo "$HOST_NAME" > /mnt/target/etc/hostname

# Configure root's bashrc file
cat >> /mnt/target/root/.bashrc << EOF

alias ll='ls -lh --color=auto'
alias lla='ls -lah --color=auto'
alias grep='grep --color=always'

PS1='\[\e[01;31m\]\h\[\e[01;34m\] \w $\[\e[00m\] '
EDITOR=vim
export PS1 EDITOR
EOF

# Disable selinux in selinux config
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /mnt/target/etc/selinux/config

# Enable ps3vram swap
echo "ps3vram" > /mnt/target/etc/modules-load.d/ps3vram.conf
echo 'KERNEL=="ps3vram", ACTION=="add", RUN+="/sbin/mkswap /dev/ps3vram", RUN+="/sbin/swapon -p 2 /dev/ps3vram"' > /mnt/target/etc/udev/rules.d/10-ps3vram.rules

# Set swappiness
echo "vm.swappiness = 10" >> /mnt/target/etc/sysctl.conf

# Configure eth0 for systemd networking
cat > /mnt/target/etc/systemd/network/10-eth0.network << EOF
[Match]
Name=eth0

[Network]
DHCP=yes
EOF

# Set systemd services
chroot /mnt/target /usr/bin/systemctl set-default multi-user.target
chroot /mnt/target /usr/bin/systemctl disable auditd.service
chroot /mnt/target /usr/bin/systemctl disable NetworkManager.service
chroot /mnt/target /usr/bin/systemctl disable NetworkManager-wait-online.service
chroot /mnt/target /usr/bin/systemctl disable wpa_supplicant.service
chroot /mnt/target /usr/bin/systemctl disable firewalld.service
chroot /mnt/target /usr/bin/systemctl disable dnf-makecache.timer
chroot /mnt/target /usr/bin/systemctl enable systemd-networkd.service
chroot /mnt/target /usr/bin/systemctl disable systemd-networkd.socket

# Configure root password
echo ""
echo "Set a root password."
echo ""
chroot /mnt/target /usr/bin/passwd root

# Unmount filesystems
umount /mnt/target/tmp
umount /mnt/target/run
umount /mnt/target/dev/pts
umount /mnt/target/dev
umount /mnt/target/sys
umount /mnt/target/proc
umount /mnt/target

# Deactivate HDD swap
swapoff /dev/ps3dd$SWAP_PART

echo ""
echo "PS3LINUX install complete."
echo "You may reboot your Playstation 3."
echo ""

exit 0

