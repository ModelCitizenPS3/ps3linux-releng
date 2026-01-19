#!/bin/bash

set -e

if (( EUID != 0 )); then
    echo "Error: This script must be run as root." >&2
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
  --boot DEVICE     device containing root partition as seen by petitboot (e.g. /dev/ps3da if PS3 is downgraded; /dev/ps3dd if PS3 is on CFW)
  --part PARTITION  number of the root partition on the boot device
  --root DEVICE     device name of the root partition as seen by the kernel (e.g. /dev/ps3dd2)
  --swap DEVICE     device name of the swap partition as seen by the kernel (e.g. /dev/ps3dd1)
  --help            show this help
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --boot)
            BOOT_DEV="$2"
            shift 2
            ;;
        --part)
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

mkswap $SWAP_PART
swapon -p 50 $SWAP_PART
mount -t ext4 $ROOT_PART /mnt/target
rm -rf /mnt/target/*
sed -i 's/enabled=1/enabled=0/g' /mnt/target/etc/yum.repos.d/fedora-updates.repo
cp -f /root/ps3linux.repo /mnt/target/etc/yum.repos.d/ps3linux.repo
dnf -y --releasever=28 --forcearch=ppc64 --installroot=/mnt/target install filesystem
rm -f /mnt/target/dev/null
mknod -m 600 /mnt/target/dev/console c 5 1
mknod -m 666 /mnt/target/dev/null c 1 3
mount -t proc /proc /mnt/target/proc
mount -t sysfs /sys /mnt/target/sys
mount -o bind /dev /mnt/target/dev
mount -o bind /dev/pts /mnt/target/dev/pts
mount -t tmpfs tmpfs /mnt/target/run
mount -t tmpfs tmpfs /mnt/target/tmp
cat > /mnt/target/etc/fstab << EOF
$ROOT_PART / ext4 noatime 0 1
$SWAP_PART swap swap pri=1 0 0
spufs /spu soufs defaults 0 0
EOF
dnf -y --releasever=28 --forcearch=ppc64 --installroot=/mnt/target groupinstall core
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /mnt/target/etc/selinux/config
echo "nameserver 8.8.8.8" > /mnt/target/etc/resolv.conf
cat > /mnt/target/etc/yaboot.conf << EOF
boot=$BOOT_DEV
partition=$PARTITION

image=/boot/vmlinuz-1.PS3.fc28.ppc64
    label=PS3LINUX
    read-only
    append="video=ps3fb:mode:1667 root=$ROOT_PART selinux=0 audit=0"
EOF
#chroot /mnt/target /usr/bin/dnf --releasever=28 --forcearch=ppc64 install bash-completion kernel kernel-core kernel-modules kernel-headers kernel-devel
umount /mnt/target/tmp
umount /mnt/target/run
umount /mnt/target/dev/pts
umount /mnt/target/dev
umount /mnt/target/sys
umount /mnt/target/proc
umount /mnt/target
echo "PS3LINUX install complete. Reboot the Playstation 3..."
exit 0

