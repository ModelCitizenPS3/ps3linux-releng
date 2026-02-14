#!/bin/bash

set -eo pipefail

if (( EUID != 0 )); then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

KVER="6.9.12"
CHROOT_PATH="$(pwd)/PS3LINUX_chroot"
KERNEL_BUILD_PATH="$(pwd)/FC28-x86_64_chroot"
LIVE_ISO_PATH="$(pwd)/PS3LINUX_LIVE_ISO"
INITRAMFS_PATH="$(pwd)/initramfs"
RESOURCES_PATH="$(pwd)/resources"
#EXCLUDES="NetworkManager,NetworkManager-libnm,libndp,sssd-common,sssd-client,libtevent,c-ares,http-parser,jansson,libdhash,libldb,libsss_certmap,libsss_idmap,libsss_nss_idmap,libtalloc,libtdb,ppc64-utils,kernel-bootwrapper,libservicelog,lsvpd,perl-Data-Dumper,perl-Errno,perl-Exporter,perl-File-Path,perl-IO,perl-PathTools,perl-Scalar-List-Utils,perl-Socket,perl-Text-Tabs+Wrap,perl-Unicode-Normalize,perl-constant,perl-interpreter,perl-libs,perl-macros,perl-parent,perl-threads,perl-threads-shared,powerpc-utils,powerpc-utils-core,bc,binutils,librtas,libvpd,perl-Carp,sg3_utils-libs,passwd,libuser,dracut,dracut-config-rescue,plymouth-scripts,firewalld,python3-dbus.python3-firewall,python3-slip,python3-slip-dbus,dbus-glib,ebtables,firewalld-filesystem,ipset,ipset-libs,iptables,libnetfilter_conntrack,libnfnetlink,python3-decorator,python3-libselinux,grub2-common,grub2-tools,grub2-tools-minimal,grubby,file,gettext,gettext-libs,libcroco,libgomp,os-prober,which,policycoreutils,libselinux-utils,openssh-clients,libedit,selinux-policy,selinux-policy-targeted,keyutils,libini_config,libverto-libev,nfs-utils,gssproxy,libbasicobjects.libcollection,libev,libevent,libnfsidmap,libpath_utils,libref_array,quota,quota-nls,rpcbind,diffutils"

if [ -d "$KERNEL_BUILD_PATH" ]; then
    echo "Error: Directory $KERNEL_BUILD_PATH exists. Please delete it." >&2
    exit 1
fi

if [ -d "$CHROOT_PATH" ]; then
    echo "Error: Directory $CHROOT_PATH exists. Please delete it." >&2
    exit 1
fi

if [ -d "$INITRAMFS_PATH" ]; then
    echo "Error: Directory $INITRAMFS_PATH exists. Please delete it." >&2
    exit 1
fi

if [ -d "$LIVE_ISO_PATH" ]; then
    echo "Error: Directory $LIVE_ISO_PATH exists. Please delete it." >&2
    exit 1
fi

mkdir -p "$KERNEL_BUILD_PATH"
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
chroot $KERNEL_BUILD_PATH /usr/bin/dnf -y --releasever=28 --forcearch=x86_64 install filesystem dnf perl-interpreter binutils gcc gcc-c++ gcc-plugin-devel make gawk bc flex bison wget tar rsync patch openssl openssl-devel zlib zlib-devel gcc-powerpc64-linux-gnu binutils-powerpc64-linux-gnu xz findutils kmod
chroot $KERNEL_BUILD_PATH /usr/bin/wget https://www.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz
chroot $KERNEL_BUILD_PATH /usr/bin/tar -xf linux-$KVER.tar.xz
cp -f $RESOURCES_PATH/0010-ps3stor-multiple-regions.patch $KERNEL_BUILD_PATH/
cp -f $RESOURCES_PATH/config-$KVER-live $KERNEL_BUILD_PATH/linux-$KVER/.config
chroot $KERNEL_BUILD_PATH /usr/bin/patch -d /linux-$KVER -p1 -i /0010-ps3stor-multiple-regions.patch
chroot $KERNEL_BUILD_PATH /usr/bin/make ARCH=powerpc CROSS_COMPILE=powerpc64-linux-gnu- -C /linux-$KVER olddefconfig
chroot $KERNEL_BUILD_PATH /usr/bin/make ARCH=powerpc CROSS_COMPILE=powerpc64-linux-gnu- -C /linux-$KVER -j1 zImage modules
chroot $KERNEL_BUILD_PATH /usr/bin/make ARCH=powerpc CROSS_COMPILE=powerpc64-linux-gnu- -C /linux-$KVER modules_install
rm -f $KERNEL_BUILD_PATH/lib/modules/$KVER/build
umount $KERNEL_BUILD_PATH/tmp
umount $KERNEL_BUILD_PATH/run
umount $KERNEL_BUILD_PATH/dev/pts
umount $KERNEL_BUILD_PATH/dev
umount $KERNEL_BUILD_PATH/sys
umount $KERNEL_BUILD_PATH/proc


mkdir -p "$CHROOT_PATH"
dnf -y --use-host-config --releasever=28 --forcearch=ppc64 --disable-repo=* --enable-repo=fedora --setopt=install_weak_deps=False --setopt=tsflags=nodocs --installroot=$CHROOT_PATH install filesystem
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
dnf -y --use-host-config --releasever=28 --forcearch=ppc64 --disable-repo=* --enable-repo=fedora --setopt=install_weak_deps=False --setopt=tsflags=nodocs --installroot=$CHROOT_PATH install dnf
sed -i 's/enabled=1/enabled=0/g' $CHROOT_PATH/etc/yum.repos.d/fedora-updates.repo
echo "ps3linux" > $CHROOT_PATH/etc/hostname
echo "nameserver 8.8.8.8" > $CHROOT_PATH/etc/resolv.conf
chroot $CHROOT_PATH /usr/bin/dnf -y --releasever=28 --forcearch=ppc64 --setopt=install_weak_deps=False --setopt=tsflags=nodocs groupinstall core
chroot $CHROOT_PATH /usr/bin/dnf -y --releasever=28 --forcearch=ppc64 --setopt=install_weak_deps=False --setopt=tsflags=nodocs install udisks2-zram bash-completion wget wpa_supplicant nano
chroot $CHROOT_PATH /usr/bin/dnf clean all
rm -f $CHROOT_PATH/etc/yum.repos.d/*.rpmnew
mv -f $CHROOT_PATH/etc/nsswitch.conf $CHROOT_PATH/etc/nsswitch.conf.orig
mv -f $CHROOT_PATH/etc/nsswitch.conf.rpmnew $CHROOT_PATH/etc/nsswitch.conf
cp -rf $KERNEL_BUILD_PATH/lib/modules/$KVER $CHROOT_PATH/lib/modules/
echo "ps3vram" > $CHROOT_PATH/etc/modules-load.d/ps3vram.conf
echo 'KERNEL=="ps3vram", ACTION=="add", RUN+="/sbin/mkswap /dev/ps3vram", RUN+="/sbin/swapon -p 200 /dev/ps3vram"' > $CHROOT_PATH/etc/udev/rules.d/10-ps3vram.rules
chmod 0200 $CHROOT_PATH/etc/shadow
sed -i '1c\root:$6$cv5wSgU5Qr51VAfB$shVUHbZViYACoKJYSou.rYODvFYemeBErPqWMaEu566QeywZcy/y7Qa0/ZAiz1y/vnTSPuphTCkqlypglOpJX/:20447:0:99999:7:::' $CHROOT_PATH/etc/shadow
chmod 0000 $CHROOT_PATH/etc/shadow
echo "vm.swappiness = 10" >> $CHROOT_PATH/etc/sysctl.conf
cat > $CHROOT_PATH/etc/systemd/network/10-eth0.network << EOF
[Match]
Name=eth0

[Network]
DHCP=yes
EOF
cat > $CHROOT_PATH/etc/systemd/network/20-wlan0.network << EOF
[Match]
Name=wlan0

[Network]
DHCP=yes
EOF
mkdir $CHROOT_PATH/mnt/target
cp $RESOURCES_PATH/zram-swap.sh $CHROOT_PATH/usr/sbin/zram-swap.sh
cp $RESOURCES_PATH/zram-swap.service $CHROOT_PATH/etc/systemd/system/zram-swap.service
cp $RESOURCES_PATH/ps3linux-install.sh $CHROOT_PATH/usr/sbin/ps3linux-install.sh
cp $RESOURCES_PATH/ps3linux.repo $CHROOT_PATH/root/ps3linux.repo
cp $RESOURCES_PATH/motd $CHROOT_PATH/root/motd
cp -f $RESOURCES_PATH/motd $CHROOT_PATH/etc/motd
cat >> $CHROOT_PATH/etc/motd << EOF

ACHTUNG: Run "ps3linux-install.sh --help"

EOF
chroot $CHROOT_PATH /usr/bin/systemctl set-default multi-user.target
chroot $CHROOT_PATH /usr/bin/systemctl disable NetworkManager.service
chroot $CHROOT_PATH /usr/bin/systemctl disable NetworkManager-wait-online.service
chroot $CHROOT_PATH /usr/bin/systemctl disable auditd.service
chroot $CHROOT_PATH /usr/bin/systemctl disable wpa_supplicant.service
chroot $CHROOT_PATH /usr/bin/systemctl disable firewalld.service
chroot $CHROOT_PATH /usr/bin/systemctl disable dnf-makecache.timer
chroot $CHROOT_PATH /usr/bin/systemctl enable systemd-networkd.service
chroot $CHROOT_PATH /usr/bin/systemctl disable systemd-networkd.socket
chroot $CHROOT_PATH /usr/bin/systemctl enable zram-swap.service
umount $CHROOT_PATH/tmp
umount $CHROOT_PATH/run
umount $CHROOT_PATH/dev/pts
umount $CHROOT_PATH/dev
umount $CHROOT_PATH/sys
umount $CHROOT_PATH/proc
rm -rf $CHROOT_PATH/usr/share/doc
rm -rf $CHROOT_PATH/usr/share/man
rm -rf $CHROOT_PATH/lib/firmware/*
find $CHROOT_PATH -type f \( -perm -111 -o -name '*.so*' -o -name '*.ko' \) -exec file {} \; | grep 'ELF' | cut -d: -f1 | while read f; do echo "Stripping $f"; powerpc64-linux-gnu-strip --strip-unneeded "$f" || true; done
find $CHROOT_PATH/usr/lib64 -name '*.a' -delete


mkdir -p $INITRAMFS_PATH/{dev,iso,lower,mnt,proc,run,sys,sysroot/{dev,proc,run,sys,tmp},tmp,usr/{bin,lib,lib64,sbin},upper/{upper,work}}
pushd $INITRAMFS_PATH
ln -s usr/bin bin
ln -s usr/lib lib
ln -s usr/lib64 lib64
ln -s usr/sbin sbin
popd
mkdir -p $INITRAMFS_PATH/lib/modules
mknod -m 600 $INITRAMFS_PATH/dev/console c 5 1
mknod -m 666 $INITRAMFS_PATH/dev/null c 1 3
cp -rf $KERNEL_BUILD_PATH/lib/modules/$KVER $INITRAMFS_PATH/lib/modules/
cp -f $RESOURCES_PATH/init $INITRAMFS_PATH/init
cp $CHROOT_PATH/usr/bin/mount $INITRAMFS_PATH/usr/bin/mount
cp $CHROOT_PATH/usr/bin/sleep $INITRAMFS_PATH/usr/bin/sleep
cp $CHROOT_PATH/usr/bin/echo $INITRAMFS_PATH/usr/bin/echo
cp $CHROOT_PATH/usr/bin/mkdir $INITRAMFS_PATH/usr/bin/mkdir
cp $CHROOT_PATH/usr/sbin/switch_root $INITRAMFS_PATH/usr/sbin/switch_root
cp $CHROOT_PATH/usr/bin/bash $INITRAMFS_PATH/usr/bin/bash
cp $CHROOT_PATH/lib64/libmount.so.1.1.0 $INITRAMFS_PATH/lib64/libmount.so.1.1.0
cp $CHROOT_PATH/lib64/libblkid.so.1.1.0 $INITRAMFS_PATH/lib64/libblkid.so.1.1.0
cp $CHROOT_PATH/lib64/libuuid.so.1.3.0 $INITRAMFS_PATH/lib64/libuuid.so.1.3.0
cp $CHROOT_PATH/lib64/librt-2.27.so $INITRAMFS_PATH/lib64/librt-2.27.so
cp $CHROOT_PATH/lib64/libselinux.so.1 $INITRAMFS_PATH/lib64/libselinux.so.1
cp $CHROOT_PATH/lib64/libc-2.27.so $INITRAMFS_PATH/lib64/libc-2.27.so
cp $CHROOT_PATH/lib64/ld-2.27.so $INITRAMFS_PATH/lib64/ld-2.27.so
cp $CHROOT_PATH/lib64/libpthread-2.27.so $INITRAMFS_PATH/lib64/libpthread-2.27.so
cp $CHROOT_PATH/lib64/libpcre2-8.so.0.7.0 $INITRAMFS_PATH/lib64/libpcre2-8.so.0.7.0
cp $CHROOT_PATH/lib64/libdl-2.27.so $INITRAMFS_PATH/lib64/libdl-2.27.so
cp $CHROOT_PATH/lib64/libtinfo.so.6.1 $INITRAMFS_PATH/lib64/libtinfo.so.6.1
pushd $INITRAMFS_PATH/usr/bin
ln -s bash sh
popd
pushd $INITRAMFS_PATH/lib64
ln -s libmount.so.1.1.0 libmount.so.1
ln -s libblkid.so.1.1.0 libblkid.so.1
ln -s libuuid.so.1.3.0 libuuid.so.1
ln -s librt-2.27.so librt.so.1
ln -s libc-2.27.so libc.so.6
ln -s ld-2.27.so ld64.so.1
ln -s libpthread-2.27.so libpthread.so.0
ln -s libpcre2-8.so.0.7.0 libpcre2-8.so.0
ln -s libdl-2.27.so libdl.so.2
ln -s libtinfo.so.6.1 libtinfo.so.6
ln -s ld-2.27.so ld-linux-x86-64.so.2
popd
pushd $INITRAMFS_PATH
mkdir -p $LIVE_ISO_PATH/{boot,etc,LiveOS}
find . | cpio -H newc -o | gzip > $LIVE_ISO_PATH/boot/initramfs.img
popd
cp -f $KERNEL_BUILD_PATH/linux-$KVER/arch/powerpc/boot/zImage $LIVE_ISO_PATH/boot/vmlinuz
cp -f $RESOURCES_PATH/yaboot.conf $LIVE_ISO_PATH/etc/yaboot.conf
mksquashfs $CHROOT_PATH $LIVE_ISO_PATH/LiveOS/liveroot.img -comp xz -b 1M -Xdict-size 100% -noappend
mkisofs -r -J -V PS3LIVE -o PS3LINUX_Live_ISO.iso $LIVE_ISO_PATH
echo ""
echo "Done. Live ISO root password: HACKTHEPLANET"
echo ""
exit 0

