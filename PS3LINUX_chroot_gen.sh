#!/bin/bash

set -eo pipefail

# Check if root
if (( EUID != 0 )); then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

CHROOT_PATH="$(pwd)/PS3LINUX_chroot"
KERNEL_BUILD_PATH="$(pwd)/FC28-x86_64_chroot"

# Build a temporary Fedora 28 (x86_64) chroot where we can cross-compile our kernel
if [ -d "$KERNEL_BUILD_PATH" ]; then
    echo "Error: Directory $KERNEL_BUILD_PATH exists." >&2
    exit 1
else
    mkdir -p "$KERNEL_BUILD_PATH"
fi

dnf -y --use-host-config --releasever=28 --forcearch=x86_64 --disable-repo=* --enable-repo=fedora --installroot=$KERNEL_BUILD_PATH install filesystem
rm -f $KERNEL_BUILD_PATH/dev/null
mknod -m 600 $KERNEL_BUILD_PATH/dev/console c 5 1
mknod -m 666 $KERNEL_BUILD_PATH/dev/null c 1 3
touch $KERNEL_BUILD_PATH/etc/fstab
mount -t proc /proc $KERNEL_BUILD_PATH/proc
mount -t sysfs /sys $KERNEL_BUILD_PATH/sys
mount -o bind /dev $KERNEL_BUILD_PATH/dev
mount -o bind /dev/pts $KERNEL_BUILD_PATH/dev/pts
mount -t tmpfs tmpfs $KERNEL_BUILD_PATH/run
mount -t tmpfs tmpfs $KERNEL_BUILD_PATH/tmp
dnf -y --use-host-config --releasever=28 --forcearch=x86_64 --disable-repo=* --enable-repo=fedora --installroot=$KERNEL_BUILD_PATH install dnf
sed -i 's/enabled=1/enabled=0/g' $KERNEL_BUILD_PATH/etc/yum.repos.d/fedora-updates.repo
echo "nameserver 8.8.8.8" > $KERNEL_BUILD_PATH/etc/resolv.conf
chroot $KERNEL_BUILD_PATH /usr/bin/dnf --releasever=28 --forcearch=x86_64 clean all
chroot $KERNEL_BUILD_PATH /usr/bin/dnf --releasever=28 --forcearch=x86_64 makecache
chroot $KERNEL_BUILD_PATH /usr/bin/dnf -y --releasever=28 --forcearch=x86_64 groupinstall core
chroot $KERNEL_BUILD_PATH /usr/bin/dnf -y --releasever=28 --forcearch=x86_64 install perl ncurses ncurses-devel binutils gcc gcc-c++ gcc-plugin-devel make gawk bc flex bison wget tar rsync patch openssl openssl-devel zlib zlib-devel binutils-powerpc64-linux-gnu gcc-powerpc64-linux-gnu
chroot $KERNEL_BUILD_PATH /usr/bin/wget https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.8.12.tar.xz
chroot $KERNEL_BUILD_PATH /usr/bin/tar xf linux-6.8.12.tar.xz
cp -f $(pwd)/resources/0011-ps3stor-multiple-regions.patch $KERNEL_BUILD_PATH/
cp -f $(pwd)/resources/config-6.8.12-live $KERNEL_BUILD_PATH/linux-6.8.12/.config
chroot $KERNEL_BUILD_PATH /usr/bin/patch -d /linux-6.8.12 -p1 -i /0011-ps3stor-multiple-regions.patch
chroot $KERNEL_BUILD_PATH /usr/bin/make ARCH=powerpc CROSS_COMPILE=powerpc64-linux-gnu- -C /linux-6.8.12 olddefconfig
chroot $KERNEL_BUILD_PATH /usr/bin/make ARCH=powerpc CROSS_COMPILE=powerpc64-linux-gnu- -C /linux-6.8.12 -j1 zImage
chroot $KERNEL_BUILD_PATH /usr/bin/make ARCH=powerpc CROSS_COMPILE=powerpc64-linux-gnu- -C /linux-6.8.12 -j1 modules
chroot $KERNEL_BUILD_PATH /usr/bin/make ARCH=powerpc CROSS_COMPILE=powerpc64-linux-gnu- -C /linux-6.8.12 modules_install
rm -f $KERNEL_BUILD_PATH/lib/modules/6.8.12/build
rm -f $KERNEL_BUILD_PATH/lib/modules/6.8.12/source
umount $KERNEL_BUILD_PATH/tmp
umount $KERNEL_BUILD_PATH/run
umount $KERNEL_BUILD_PATH/dev/pts
umount $KERNEL_BUILD_PATH/dev
umount $KERNEL_BUILD_PATH/sys
umount $KERNEL_BUILD_PATH/proc

if [ -d "$CHROOT_PATH" ]; then
    echo "Error: Directory $CHROOT_PATH exists." >&2
    exit 1
else
    mkdir -pv "$CHROOT_PATH"
fi

dnf -y --use-host-config --releasever=28 --forcearch=ppc64 --disable-repo=* --enable-repo=fedora --repofrompath=ps3linux,http://www.ps3linux.net/ps3linux-repos/ps3linux/ppc64/ --no-gpgchecks --setopt=install_weak_deps=False --setopt=tsflags=nodocs --exclude=fedora-release --installroot=$CHROOT_PATH install filesystem

rm -f $CHROOT_PATH/dev/null
mknod -m 600 $CHROOT_PATH/dev/console c 5 1
mknod -m 666 $CHROOT_PATH/dev/null c 1 3
touch $CHROOT_PATH/etc/fstab

mount -t proc /proc $CHROOT_PATH/proc
mount -t sysfs /sys $CHROOT_PATH/sys
mount -o bind /dev $CHROOT_PATH/dev
mount -o bind /dev/pts $CHROOT_PATH/dev/pts
mount -t tmpfs tmpfs $CHROOT_PATH/run
mount -t tmpfs tmpfs $CHROOT_PATH/tmp

dnf -y --use-host-config --releasever=28 --forcearch=ppc64 --disable-repo=* --enable-repo=fedora --repofrompath=ps3linux,http://www.ps3linux.net/ps3linux-repos/ps3linux/ppc64/ --no-gpgchecks --setopt=install_weak_deps=False --setopt=tsflags=nodocs --exclude=fedora-release --installroot=$CHROOT_PATH install dnf

sed -i 's/enabled=1/enabled=0/g' $CHROOT_PATH/etc/yum.repos.d/fedora-updates.repo
cp -fv $(pwd)/resources/ps3linux.repo $CHROOT_PATH/etc/yum.repos.d/ps3linux.repo
echo "ps3linux" > $CHROOT_PATH/etc/hostname
echo "nameserver 8.8.8.8" > $CHROOT_PATH/etc/resolv.conf

chroot $CHROOT_PATH /usr/bin/dnf --releasever=28 --forcearch=ppc64 clean all
chroot $CHROOT_PATH /usr/bin/dnf --releasever=28 --forcearch=ppc64 makecache
chroot $CHROOT_PATH /usr/bin/dnf -y --releasever=28 --forcearch=ppc64 --setopt=install_weak_deps=False --setopt=tsflags=nodocs groupinstall core
chroot $CHROOT_PATH /usr/bin/dnf -y --releasever=28 --forcearch=ppc64 --setopt=install_weak_deps=False --setopt=tsflags=nodocs install udisks2-zram nfs-utils bash-completion wget wpa_supplicant dosfstools NetworkManager-wifi NetworkManager-tui
chroot $CHROOT_PATH /usr/bin/dnf clean all

rm -f $CHROOT_PATH/etc/yum.repos.d/*.rpmnew
mv -f $CHROOT_PATH/etc/nsswitch.conf $CHROOT_PATH/etc/nsswitch.conf.orig
mv -f $CHROOT_PATH/etc/nsswitch.conf.rpmnew $CHROOT_PATH/etc/nsswitch.conf
rm -rf $CHROOT_PATH/usr/share/doc
rm -rf $CHROOT_PATH/usr/share/man
rm -rf $CHROOT_PATH/lib/firmware/*
cp -rf $KERNEL_BUILD_PATH/lib/modules/6.8.12 $CHROOT_PATH/lib/modules/

echo "ps3vram" > $CHROOT_PATH/etc/modules-load.d/ps3vram.conf
echo 'KERNEL=="ps3vram", ACTION=="add", RUN+="/sbin/mkswap /dev/ps3vram", RUN+="/sbin/swapon -p 200 /dev/ps3vram"' > $CHROOT_PATH/etc/udev/rules.d/10-ps3vram.rules
chmod 0200 $CHROOT_PATH/etc/shadow
sed -i '1c\root:$6$cv5wSgU5Qr51VAfB$shVUHbZViYACoKJYSou.rYODvFYemeBErPqWMaEu566QeywZcy/y7Qa0/ZAiz1y/vnTSPuphTCkqlypglOpJX/:20447:0:99999:7:::' $CHROOT_PATH/etc/shadow
chmod 0000 $CHROOT_PATH/etc/shadow
mkdir $CHROOT_PATH/mnt/target
cp $(pwd)/resources/zram-swap.sh $CHROOT_PATH/usr/sbin/zram-swap.sh
cp $(pwd)/resources/zram-swap.service $CHROOT_PATH/etc/systemd/system/zram-swap.service
cp $(pwd)/resources/ps3linux-install.sh $CHROOT_PATH/usr/sbin/ps3linux-install.sh

chroot $CHROOT_PATH /usr/bin/systemctl disable auditd.service
chroot $CHROOT_PATH /usr/bin/systemctl disable firewalld.service
chroot $CHROOT_PATH /usr/bin/systemctl disable dbus-org.fedoraproject.FirewallD1.service
chroot $CHROOT_PATH /usr/bin/systemctl disable dnf-makecache.timer
chroot $CHROOT_PATH /usr/bin/systemctl enable zram-swap.service

umount $CHROOT_PATH/tmp
umount $CHROOT_PATH/run
umount $CHROOT_PATH/dev/pts
umount $CHROOT_PATH/dev
umount $CHROOT_PATH/sys
umount $CHROOT_PATH/proc

find $CHROOT_PATH -type f \( -perm -111 -o -name '*.so*' -o -name '*.ko' \) -exec file {} \; | grep 'ELF' | cut -d: -f1 | while read f; do echo "Stripping $f"; powerpc64-linux-gnu-strip --strip-unneeded "$f" || true; done
find $CHROOT_PATH/usr/lib64 -name '*.a' -delete

echo "Done."
echo "Password for root: HACKTHEPLANET"

exit 0

