#!/bin/sh

set -euo pipefail

[ $(id -u) -eq 0 ] || exit 1

CHROOT_PATH=$(pwd)/PS3LINUX_chroot
KERNEL_BUILD_PATH=$(pwd)/resources/FC28-x86_64

mkdir $KERNEL_BUILD_PATH
dnf -y --use-host-config --forcearch=x86_64 --releasever=28 --disable-repo=* --enable-repo=fedora --installroot=$KERNEL_BUILD_PATH install filesystem
rm -fv $KERNEL_BUILD_PATH/dev/null
mknod -m 600 $KERNEL_BUILD_PATH/dev/console c 5 1
mknod -m 666 $KERNEL_BUILD_PATH/dev/null c 1 3
touch $KERNEL_BUILD_PATH/etc/fstab
mount -t proc /proc $KERNEL_BUILD_PATH/proc
mount -t sysfs /sys $KERNEL_BUILD_PATH/sys
mount -o bind /dev $KERNEL_BUILD_PATH/dev
mount -o bind /dev/pts $KERNEL_BUILD_PATH/dev/pts
mount -t tmpfs tmpfs $KERNEL_BUILD_PATH/run
mount -t tmpfs tmpfs $KERNEL_BUILD_PATH/tmp
dnf -y --use-host-config --forcearch=x86_64 --releasever=28 --disable-repo=* --enable-repo=fedora --installroot=$KERNEL_BUILD_PATH install dnf
sed -i 's/enabled=1/enabled=0/g' $KERNEL_BUILD_PATH/etc/yum.repos.d/fedora-updates.repo
echo "nameserver 8.8.8.8" > $KERNEL_BUILD_PATH/etc/resolv.conf
chroot $KERNEL_BUILD_PATH /usr/bin/dnf --forcearch=x86_64 --releasever=28 clean all
chroot $KERNEL_BUILD_PATH /usr/bin/dnf --forcearch=x86_64 --releasever=28 makecache
chroot $KERNEL_BUILD_PATH /usr/bin/dnf -y --forcearch=x86_64 --releasever=28 groupinstall core
chroot $KERNEL_BUILD_PATH /usr/bin/dnf -y --forcearch=x86_64 install ncurses ncurses-devel binutils make gcc gcc-c++ gcc-plugin-devel bc flex bison wget tar tree rsync patch openssl-* zlib-* perl binutils-powerpc64-linux-gnu gcc-powerpc64-linux-gnu
chroot $KERNEL_BUILD_PATH /usr/bin/wget https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.0.19.tar.xz
chroot $KERNEL_BUILD_PATH /usr/bin/tar xf linux-6.0.19.tar.xz
cp -r $(pwd)/resources/patches-6.0.19 $KERNEL_BUILD_PATH/
cp $(pwd)/resources/config-6.0.19-live $KERNEL_BUILD_PATH/linux-6.0.19/.config
chroot $KERNEL_BUILD_PATH /usr/bin/patch -d /linux-6.0.19 -p1 -i /patches-6.0.19/0009-ps3disk-blk_mq_queue_stopped.patch
chroot $KERNEL_BUILD_PATH /usr/bin/patch -d /linux-6.0.19 -p1 -i /patches-6.0.19/0010-ps3stor-multiple-regions.patch
chroot $KERNEL_BUILD_PATH /usr/bin/patch -d /linux-6.0.19 -p1 -i /patches-6.0.19/0011-ps3stor-send-cmd-timeout.patch
chroot $KERNEL_BUILD_PATH /usr/bin/patch -d /linux-6.0.19 -p1 -i /patches-6.0.19/0035-ps3-partition.patch
chroot $KERNEL_BUILD_PATH /usr/bin/patch -d /linux-6.0.19 -p1 -i /patches-6.0.19/0080-ps3rom-vendor-specific-command.patch
chroot $KERNEL_BUILD_PATH /usr/bin/patch -d /linux-6.0.19 -p1 -i /patches-6.0.19/1000-ps3disk-fix-bvec-memcpy.patch
chroot $KERNEL_BUILD_PATH /usr/bin/patch -d /linux-6.0.19 -p1 -i /patches-6.0.19/1010-ppc-asm-uaccess-address.patch
chroot $KERNEL_BUILD_PATH /usr/bin/make ARCH=powerpc CROSS_COMPILE=powerpc64-linux-gnu- -C /linux-6.0.19 oldconfig
chroot $KERNEL_BUILD_PATH /usr/bin/make ARCH=powerpc CROSS_COMPILE=powerpc64-linux-gnu- -C /linux-6.0.19 -j2 zImage
chroot $KERNEL_BUILD_PATH /usr/bin/make ARCH=powerpc CROSS_COMPILE=powerpc64-linux-gnu- -C /linux-6.0.19 -j1 modules
chroot $KERNEL_BUILD_PATH /usr/bin/make ARCH=powerpc CROSS_COMPILE=powerpc64-linux-gnu- -C /linux-6.0.19 modules_install
[ -f $(pwd)/resources/vmlinuz ] && rm $(pwd)/resources/vmlinuz
cp $KERNEL_BUILD_PATH/linux-6.0.19/arch/powerpc/boot/zImage $(pwd)/resources/vmlinuz
[ -d $(pwd)/resources/6.0.19 ] && rm -rf $(pwd)/resources/6.0.19
rm -f $KERNEL_BUILD_PATH/lib/modules/6.0.19/build
rm -f $KERNEL_BUILD_PATH/lib/modules/6.0.19/source
cp -r $KERNEL_BUILD_PATH/lib/modules/6.0.19 $(pwd)/resources/
umount $KERNEL_BUILD_PATH/tmp
umount $KERNEL_BUILD_PATH/run
umount $KERNEL_BUILD_PATH/dev/pts
umount $KERNEL_BUILD_PATH/dev
umount $KERNEL_BUILD_PATH/sys
umount $KERNEL_BUILD_PATH/proc
rm -rf $KERNEL_BUILD_PATH

[ -d $CHROOT_PATH ] && rm -rf $CHROOT_PATH
mkdir $CHROOT_PATH

dnf -y --use-host-config --forcearch=ppc64 --releasever=28 --disable-repo=* --enable-repo=fedora --repofrompath=ps3linux,http://www.ps3linux.net/ps3linux-repos/ps3linux/ppc64/ --no-gpgchecks --setopt=install_weak_deps=False --setopt=tsflags=nodocs --exclude=fedora-release --installroot=$CHROOT_PATH install filesystem

rm -fv $CHROOT_PATH/dev/null
mknod -m 600 $CHROOT_PATH/dev/console c 5 1
mknod -m 666 $CHROOT_PATH/dev/null c 1 3
touch $CHROOT_PATH/etc/fstab

mount -t proc /proc $CHROOT_PATH/proc
mount -t sysfs /sys $CHROOT_PATH/sys
mount -o bind /dev $CHROOT_PATH/dev
mount -o bind /dev/pts $CHROOT_PATH/dev/pts
mount -t tmpfs tmpfs $CHROOT_PATH/run
mount -t tmpfs tmpfs $CHROOT_PATH/tmp

dnf -y --use-host-config --forcearch=ppc64 --releasever=28 --disable-repo=* --enable-repo=fedora --repofrompath=ps3linux,http://www.ps3linux.net/ps3linux-repos/ps3linux/ppc64/ --no-gpgchecks --setopt=install_weak_deps=False --setopt=tsflags=nodocs --installroot=$CHROOT_PATH install dnf

sed -i 's/enabled=1/enabled=0/g' $CHROOT_PATH/etc/yum.repos.d/fedora-updates.repo
cat > $CHROOT_PATH/etc/yum.repos.d/ps3linux.repo << EOF
[ps3linux]
name=ps3linux - ppc64
baseurl=http://www.ps3linux.net/ps3linux-repos/ps3linux/ppc64/
enabled=1
gpgcheck=0

[ps3linux-debuginfo]
name=ps3linux - ppc64 - Debug
baseurl=http://www.ps3linux.net/ps3linux-repos/ps3linux/debug/
enabled=0
gpgcheck=0

[ps3linux-source]
name=ps3linux - Source
baseurl=http://www.ps3linux.net/ps3linux-repos/ps3linux/SRPMS/
enabled=0
gpgcheck=0
EOF
sed -i 's/ppc64/$basearch/g' $CHROOT_PATH/etc/yum.repos.d/ps3linux.repo

echo "ps3linux" > $CHROOT_PATH/etc/hostname
echo "nameserver 8.8.8.8" > $CHROOT_PATH/etc/resolv.conf
echo "nameserver 8.8.4.4" >> $CHROOT_PATH/etc/resolv.conf

chroot $CHROOT_PATH /usr/bin/dnf --releasever=28 clean all
chroot $CHROOT_PATH /usr/bin/dnf --releasever=28 makecache
chroot $CHROOT_PATH /usr/bin/dnf -y --releasever=28 --setopt=install_weak_deps=False --setopt=tsflags=nodocs groupinstall core
chroot $CHROOT_PATH /usr/bin/dnf -y --setopt=install_weak_deps=False --setopt=tsflags=nodocs install udisks2-zram nfs-utils bash-completion wget gdisk
chroot $CHROOT_PATH /usr/bin/dnf clean all

rm -f $CHROOT_PATH/etc/yum.repos.d/*.rpmnew
mv -f $CHROOT_PATH/etc/nsswitch.conf $CHROOT_PATH/etc/nsswitch.conf.orig
mv -f $CHROOT_PATH/etc/nsswitch.conf.rpmnew $CHROOT_PATH/etc/nsswitch.conf

rm -rf $CHROOT_PATH/usr/share/doc
rm -rf $CHROOT_PATH/usr/share/man
rm -rf $CHROOT_PATH/lib/firmware/*
cp -rf $(pwd)/resources/6.0.19 $CHROOT_PATH/lib/modules/

cat > $CHROOT_PATH/etc/systemd/network/10-eth0.network << EOF
[Match]
Name=eth0

[Network]
DHCP=yes
EOF

echo "ps3vram" > $CHROOT_PATH/etc/modules-load.d/ps3vram.conf
echo 'KERNEL=="ps3vram", ACTION=="add", RUN+="/sbin/mkswap /dev/ps3vram", RUN+="/sbin/swapon -p 200 /dev/ps3vram"' > $CHROOT_PATH/etc/udev/rules.d/10-ps3vram.rules
chmod 0200 $CHROOT_PATH/etc/shadow
sed -i '1c\root:$6$cv5wSgU5Qr51VAfB$shVUHbZViYACoKJYSou.rYODvFYemeBErPqWMaEu566QeywZcy/y7Qa0/ZAiz1y/vnTSPuphTCkqlypglOpJX/:20447:0:99999:7:::' $CHROOT_PATH/etc/shadow
chmod 0000 $CHROOT_PATH/etc/shadow
mkdir $CHROOT_PATH/mnt/target
cp $(pwd)/resources/zram-swap.sh $CHROOT_PATH/usr/sbin/zram-swap.sh

cat > $CHROOT_PATH/etc/systemd/system/zram-swap.service << EOF
[Unit]
Description=ZRAM Swap Setup
DefaultDependencies=no
After=zram-setup@.service
Before=swap.target
ConditionPathExists=/sys/block/zram0

[Service]
Type=oneshot
ExecStart=/usr/sbin/zram-swap.sh
RemainAfterExit=yes

[Install]
WantedBy=swap.target
EOF

cp $(pwd)/resources/ps3linux-install.sh $CHROOT_PATH/usr/sbin/ps3linux-install.sh

chroot $CHROOT_PATH /usr/bin/systemctl mask auth-rpcgss-module.service
chroot $CHROOT_PATH /usr/bin/systemctl mask rpc-gssd.service
chroot $CHROOT_PATH /usr/bin/systemctl mask systemd-tmpfiles-setup.service
chroot $CHROOT_PATH /usr/bin/systemctl mask systemd-update-utmp.service
chroot $CHROOT_PATH /usr/bin/systemctl disable auditd.service
chroot $CHROOT_PATH /usr/bin/systemctl disable fedora-import-state.service
chroot $CHROOT_PATH /usr/bin/systemctl disable fedora-readonly.service
chroot $CHROOT_PATH /usr/bin/systemctl disable mdmonitor.service
chroot $CHROOT_PATH /usr/bin/systemctl disable multipathd.service
chroot $CHROOT_PATH /usr/bin/systemctl disable sssd-secrets.socket
chroot $CHROOT_PATH /usr/bin/systemctl disable sssd.service
chroot $CHROOT_PATH /usr/bin/systemctl disable firewalld.service
chroot $CHROOT_PATH /usr/bin/systemctl disable dbus-org.fedoraproject.FirewallD1.service
chroot $CHROOT_PATH /usr/bin/systemctl disable NetworkManager.service
chroot $CHROOT_PATH /usr/bin/systemctl disable dbus-org.freedesktop.nm-dispatcher.service
chroot $CHROOT_PATH /usr/bin/systemctl disable dbus-org.freedesktop.NetworkManager.service
chroot $CHROOT_PATH /usr/bin/systemctl disable NetworkManager-wait-online.service
chroot $CHROOT_PATH /usr/bin/systemctl disable dnf-makecache.timer
chroot $CHROOT_PATH /usr/bin/systemctl enable systemd-networkd.service
chroot $CHROOT_PATH /usr/bin/systemctl enable zram-swap.service

chroot $CHROOT_PATH /usr/bin/ssh-keygen -t rsa -N '' -f /etc/ssh/ssh_host_rsa_key
chroot $CHROOT_PATH /usr/bin/ssh-keygen -t ecdsa -N '' -f /etc/ssh/ssh_host_ecdsa_key
chroot $CHROOT_PATH /usr/bin/ssh-keygen -t ed25519 -N '' -f /etc/ssh/ssh_host_ed25519_key

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

