#!/bin/bash

set -eo pipefail

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

echo "~~~~~~~~~~~~~~~~~~~~~~~"
echo "PS3LINUX INSTALL SCRIPT"
echo "~~~~~~~~~~~~~~~~~~~~~~~"
mkswap $SWAP_PART
swapon -p 50 $SWAP_PART
echo "Formatting root partition. Select y to continue..."
mkfs -t ext4 $ROOT_PART
echo "Mounting root partition at /mnt/target..."
mount -t ext4 $ROOT_PART /mnt/target
rm -rf /mnt/target/*
echo "Building dnf metadata cache (patience is a virtue)..."
dnf -y --releasever=28 --forcearch=ppc64 --installroot=/mnt/target install filesystem
rm -f /mnt/target/dev/null
mknod -m 600 /mnt/target/dev/console c 5 1
mknod -m 666 /mnt/target/dev/null c 1 3
echo "Mounting virtual ker filesystems..."
mount -t proc /proc /mnt/target/proc
mount -t sysfs /sys /mnt/target/sys
mount -o bind /dev /mnt/target/dev
mount -o bind /dev/pts /mnt/target/dev/pts
mount -t tmpfs tmpfs /mnt/target/run
mount -t tmpfs tmpfs /mnt/target/tmp
echo "Generating target fstab file..."
cat > /mnt/target/etc/fstab << EOF
$ROOT_PART / ext4 noatime 0 1
$SWAP_PART swap swap pri=1 0 0
spufs /spu spufs defaults 0 0
EOF
echo "Preparing target repo configs..."
cp -f /etc/yum.repos.d/ps3linux.repo /mnt/target/etc/yum.repos.d/ps3linux.repo
sed -i 's/enabled=1/enabled=0/g' /mnt/target/etc/yum.repos.d/fedora-updates.repo
echo "Installing dnf core package group..."
dnf -y --releasever=28 --forcearch=ppc64 --installroot=/mnt/target groupinstall core
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /mnt/target/etc/selinux/config
echo "Configuring target system..."
echo 'KERNEL=="ps3vram", ACTION=="add", RUN+="/sbin/mkswap /dev/ps3vram", RUN+="/sbin/swapon -p 2 /dev/ps3vram"' > /mnt/target/etc/udev/rules.d/10-ps3vram.rules
echo "nameserver 8.8.8.8" > /mnt/target/etc/resolv.conf
cat > /mnt/target/etc/yaboot.conf << EOF
boot=$BOOT_DEV
partition=$PARTITION
EOF
echo "Installing kernel (and some other packages)..."
chroot /mnt/target /usr/bin/dnf -y --releasever=28 --forcearch=ppc64 install passwd bash-completion kernel-6.8.12-1.PS3.fc28 kernel-core-6.8.12-1.PS3.fc28 kernel-modules-6.8.12-1.PS3.fc28 kernel-headers-6.8.12-1.PS3.fc28 kernel-cross-headers-6.8.12-1.PS3.fc28 kernel-devel-6.8.12-1.PS3.fc28
echo "Setting up bootloader config yaboot.conf..."
sed -i "s|append=|append=\"video=ps3fb:mode:1667 root=$ROOT_PART selinux=0 audit=0\"|" /mnt/target/etc/yaboot.conf
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo "Please Set a root password..."
echo "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
chroot /mnt/target /usr/bin/passwd root
echo "Unmounting virtual filesystems..."
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
exit 0

