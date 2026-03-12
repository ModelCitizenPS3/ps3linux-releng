#!/bin/bash

set -eo pipefail

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

  --help                show this help

EXAMPLE: ps3linux-install.sh --boot /dev/ps3da --root 2 --swap 1

NOTE: This script should only be run after your PS3's HDD has been partitioned
      and contains at least one root partition and one swap partition. You can
      partition the drive by running fdisk /dev/ps3dd from the command line.
    
Suggested layout: Name          Type         Size
                  /dev/ps3dd1   Linux Swap   2 GiB (2048 MiB)
                  /dev/ps3dd2   Linux        remainder of drive

EOF
    exit 1
}

BOOT_DEV=""
ROOT_PART=""
SWAP_PART=""

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
echo "Formatting root partition as ext4. Select y to continue."
mkfs -t ext4 /dev/ps3dd$ROOT_PART
mount -t ext4 /dev/ps3dd$ROOT_PART /mnt/target
rm -rf /mnt/target/*

# Install root filesystem and mount virtual filesystems
dnf -y --releasever=28 --forcearch=ppc64 --disablerepo=updates --disablerepo=updates-testing --installroot=/mnt/target --repofrompath=ps3linux,https://ps3linux.net/ps3linux-repos/ppc64/ --nogpgcheck install filesystem
rm -f /mnt/target/dev/null
mknod -m 600 /mnt/target/dev/console c 5 1
mknod -m 666 /mnt/target/dev/null c 1 3
mount -t proc /proc /mnt/target/proc
mount -t sysfs /sys /mnt/target/sys
mount -o bind /dev /mnt/target/dev
mount -o bind /dev/pts /mnt/target/dev/pts
mount -t tmpfs tmpfs /mnt/target/run
mount -t tmpfs tmpfs /mnt/target/tmp

# Create fstab, configure dnf repos, create yaboot.conf
cat > /mnt/target/etc/fstab << EOF
/dev/ps3dd$ROOT_PART / ext4 noatime 0 1
/dev/ps3dd$SWAP_PART swap swap pri=1 0 0
spufs /spu spufs defaults 0 0
EOF

# Install core package group
dnf -y --releasever=28 --forcearch=ppc64 --disablerepo=updates --disablerepo=updates-testing --installroot=/mnt/target --repofrompath=ps3linux,https://ps3linux.net/ps3linux-repos/ppc64/ --nogpgcheck groupinstall core
echo "export PS1='\[\e[01;31m\]\h\[\e[01;34m\] \w $\[\e[00m\] '" >> /mnt/target/root/.bashrc
sed -i 's/enabled=1/enabled=0/g' /mnt/target/etc/yum.repos.d/fedora-updates.repo
cp /root/ps3linux.repo /mnt/target/etc/yum.repos.d/ps3linux.repo
cp -f /root/motd /mnt/target/etc/motd
echo "nameserver 8.8.8.8" > /mnt/target/etc/resolv.conf
cat > /mnt/target/etc/yaboot.conf << EOF
boot=$BOOT_DEV
partition=$ROOT_PART
EOF
chroot /mnt/target /usr/bin/dnf -y --releasever=28 --forcearch=ppc64 --disablerepo=updates --disablerepo=updates-testing --enablerepo=ps3linux install kernel kernel-core kernel-modules kernel-headers bash-completion nfs-utils rsyslog wpa_supplicant dosfstools vim nano lynx
sed -i "s|append=\"\"|append=\"video=ps3fb:mode:1669 root=/dev/ps3dd$ROOT_PART selinux=0 audit=0\"|" /mnt/target/etc/yaboot.conf

# Perform remaining configuration
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /mnt/target/etc/selinux/config
echo 'KERNEL=="ps3vram", ACTION=="add", RUN+="/sbin/mkswap /dev/ps3vram", RUN+="/sbin/swapon -p 2 /dev/ps3vram"' > /mnt/target/etc/udev/rules.d/10-ps3vram.rules
echo "vm.swappiness = 10" >> /mnt/target/etc/sysctl.conf
echo "ps3vram" > /mnt/target/etc/modules-load.d/ps3vram.conf
cat > /mnt/target/etc/systemd/network/10-eth0.network << EOF
[Match]
Name=eth0

[Network]
DHCP=yes
EOF
chroot /mnt/target /usr/bin/systemctl set-default multi-user.target
chroot /mnt/target /usr/bin/systemctl disable auditd.service
chroot /mnt/target /usr/bin/systemctl disable NetworkManager.service
chroot /mnt/target /usr/bin/systemctl disable NetworkManager-wait-online.service
chroot /mnt/target /usr/bin/systemctl disable wpa_supplicant.service
chroot /mnt/target /usr/bin/systemctl disable firewalld.service
chroot /mnt/target /usr/bin/systemctl disable dnf-makecache.timer
chroot /mnt/target /usr/bin/systemctl enable systemd-networkd.service
chroot /mnt/target /usr/bin/systemctl disable systemd-networkd.socket
echo "Set a root password."
chroot /mnt/target /usr/bin/passwd root

# Unmount filesystems
umount /mnt/target/tmp
umount /mnt/target/run
umount /mnt/target/dev/pts
umount /mnt/target/dev
umount /mnt/target/sys
umount /mnt/target/proc
umount /mnt/target
echo ""
echo "PS3LINUX install complete."
echo "You may reboot your Playstation 3."
echo ""

