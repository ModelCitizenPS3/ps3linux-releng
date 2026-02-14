#!/bin/bash

set -eo pipefail

if (( EUID != 0 )); then
    echo "Error! This script must be run as root." >&2
    exit 1
fi

BOOT_DEV=""
PARTITION=""
ROOT_PART=""
SWAP_PART=""

usage() {
    cat << EOF
Usage: $0 [options]

Options:
  --boot DEVICE             device containing root partition (as seen by petitboot)
                            use /dev/ps3da if your PS3 is downgraded (on Sony Firmware <= 3.15)
                            use /dev/ps3dd if PS3 is on Custom Firmware (like Rebug or Evilnat)
  --partition PARTITION     number of the root partition (on the boot device)
                            example: 2
  --root DEVICE             name and partition number of the root device as seen by the kernel
                            example: /dev/ps3dd2
  --swap DEVICE             name and partition number of the swap device as seen by the kernel
                            example: /dev/ps3dd1
  --help                    show this help

NOTE: This script should only be run AFTER the PS3's Linux drive (/dev/ps3da or /dev/ps3dd) has
      been partitioned. You can partition the PS3's Linux HDD with fdisk.
    
      Suggested layout: Name        Type        Size
                        /dev/ps3dd1 Linux Swap  2 GiB (2048 MiB)
                        /dev/ps3dd2 Linux       remainder of drive (use this partition as root)

EOF
    exit 1
}

if [ "$#" -eq 0 ]; then
    echo "Error: No arguments provided." >&2
    usage
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --boot)
            BOOT_DEV="$2"
            shift 2
            ;;
        --partition)
            PARTITION="$2"
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
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

echo ""
echo "~~~~~~~~~~~~~~~~~~~~~~~"
echo "PS3LINUX INSTALL SCRIPT"
echo "~~~~~~~~~~~~~~~~~~~~~~~"
echo ""

# Activate HDD swap partition
mkswap $SWAP_PART
swapon -p 50 $SWAP_PART

# Format and mount root partition
echo "Formatting root partition as ext4. Select y to continue."
mkfs -t ext4 $ROOT_PART
mount -t ext4 $ROOT_PART /mnt/target
rm -rf /mnt/target/*

# Create root filesystem and mount virtual filesystems
dnf -y --releasever=28 --forcearch=ppc64 --installroot=/mnt/target --repofrompath=ps3linux,http://www.ps3linux.net/ps3linux-repos/ppc64/ --nogpgcheck install filesystem
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
$ROOT_PART / ext4 noatime 0 1
$SWAP_PART swap swap pri=1 0 0
spufs /spu spufs defaults 0 0
EOF

# Install core package group, kernel packages, and any additional packages
dnf -y --releasever=28 --forcearch=ppc64 --installroot=/mnt/target --repofrompath=ps3linux,http://www.ps3linux.net/ps3linux-repos/ppc64/ --nogpgcheck groupinstall core
sed -i 's/enabled=1/enabled=0/g' /mnt/target/etc/yum.repos.d/fedora-updates.repo
cp /root/ps3linux.repo /mnt/target/etc/yum.repos.d/ps3linux.repo
cp -f /root/motd /mnt/target/etc/motd
echo "nameserver 8.8.8.8" > /mnt/target/etc/resolv.conf
cat > /mnt/target/etc/yaboot.conf << EOF
boot=$BOOT_DEV
partition=$PARTITION
EOF
chroot /mnt/target /usr/bin/dnf -y --releasever=28 --forcearch=ppc64 install kernel kernel-headers bash-completion nfs-utils wpa_supplicant dnf-utils dosfstools tree sed man-db vim nano
sed -i "s|append=\"\"|append=\"video=ps3fb:mode:1669 root=$ROOT_PART selinux=0 audit=0\"|" /mnt/target/etc/yaboot.conf

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
cat > /mnt/target/etc/systemd/network/20-wlan0.network << EOF
[Match]
Name=wlan0

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
echo ""
echo "~~~~~~~~~~~~~~~~~~~~~~"
echo "Set a root password..."
echo "~~~~~~~~~~~~~~~~~~~~~~"
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
echo ""
echo "PS3LINUX install complete."
echo "You may reboot your Playstation 3."
echo ""
exit 0

