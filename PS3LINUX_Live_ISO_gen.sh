#!/bin/bash

set -eo pipefail

# Check if we have root privileges
if [ $(id -u) -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Variables
KEEP=0
KVER=6.18.52
CHROOT_PATH=$(pwd)/PS3LINUX_ppc64_chroot
LIVE_ISO_PATH=$(pwd)/PS3LINUX_Live_ISO
INITRAMFS_PATH=$(pwd)/initramfs
RESOURCES_PATH=$(pwd)/resources

# Usage message
usage() {
   cat << EOF
Usage: PS3LINUX_Live_ISO_gen.sh [options]

Options:
    --keep      Do not delete the ppc64 chroot directory generated during the build.
                You can use this chroot for developing and packaging software for PS3LINUX.
    --help      Show this help

EOF
}

# Unmount all virtual filesystems from chroot
umounts() {
    echo EXIT 1
    umount -v $CHROOT_PATH/tmp
    umount -v $CHROOT_PATH/run
    umount -v $CHROOT_PATH/dev/pts
    umount -v $CHROOT_PATH/dev
    umount -v $CHROOT_PATH/sys
    umount -v $CHROOT_PATH/proc
    exit 1
}

# Parse command line arguments
for arg in "$@"; do
    case "$arg" in
        --keep)
            KEEP=1
            shift 1
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Error. Unknown argument: $arg"
            usage
            exit 1
            ;;
    esac
done

# Check if subdirectories for build already exist
if [ -d $CHROOT_PATH ]; then
    echo "Error: Directory $CHROOT_PATH exists. Please delete it." >&2
    exit 1
fi
if [ -d $INITRAMFS_PATH ]; then
    echo "Error: Directory $INITRAMFS_PATH exists. Please delete it." >&2
    exit 1
fi
if [ -d $LIVE_ISO_PATH ]; then
    echo "Error: Directory $LIVE_ISO_PATH exists. Please delete it." >&2
    exit 1
fi
if [ -d $(pwd)/linux-$KVER ]; then
    echo "Error: Directory linux-$KVER exists. Please delete it." >&2
    exit 1
fi

# Cross compile a kernel
wget https://www.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz
tar xvf linux-$KVER.tar.xz
pushd linux-$KVER
patch -p1 < $RESOURCES_PATH/0001-ps3stor-multiple-regions.patch
patch -p1 < $RESOURCES_PATH/0002-spufs-fix-deadlock-and-dir-lifetimes.patch
cp -fv $RESOURCES_PATH/config-live .config
ARCH=powerpc CROSS_COMPILE=powerpc64-linux-gnu- make olddefconfig
ARCH=powerpc CROSS_COMPILE=powerpc64-linux-gnu- make zImage modules
ARCH=powerpc CROSS_COMPILE=powerpc64-linux-gnu- INSTALL_MOD_PATH=$(pwd)/../kmods INSTALL_MOD_STRIP=1 make modules_install
popd

# Create chroot directory. This will become our live ISO's root filesystem.
mkdir -pv "$CHROOT_PATH"

# Install root filesystem into chroot directory
dnf -y --use-host-config --releasever=28 --forcearch=ppc64 --disable-repo=* --enable-repo=fedora --setopt=install_weak_deps=False --setopt=tsflags=nodocs --installroot=$CHROOT_PATH install filesystem

# Delete empty file
rm -fv $CHROOT_PATH/dev/null

# Make some nodes in dev directory and mount virtual filesystems
mknod -m 600 $CHROOT_PATH/dev/console c 5 1
mknod -m 666 $CHROOT_PATH/dev/null c 1 3
mount -vt proc /proc $CHROOT_PATH/proc
mount -vt sysfs /sys $CHROOT_PATH/sys
mount -vo bind /dev $CHROOT_PATH/dev
mount -vo bind /dev/pts $CHROOT_PATH/dev/pts
mount -vt tmpfs tmpfs $CHROOT_PATH/run
mount -vt tmpfs tmpfs $CHROOT_PATH/tmp

# Some packages look for this file 
touch $CHROOT_PATH/etc/fstab || umounts

# Install dnf package manager into chroot directory
dnf -y --releasever=28 --forcearch=ppc64 --disable-repo=* --enable-repo=fedora --setopt=install_weak_deps=False --setopt=tsflags=nodocs --installroot=$CHROOT_PATH install dnf || umounts

# Enable networking for chroot
echo "nameserver 8.8.8.8" > $CHROOT_PATH/etc/resolv.conf || umounts
echo "nameserver 8.8.4.4" >> $CHROOT_PATH/etc/resolv.conf || umounts

# Install "core" dnf package group inside chroot directory
chroot $CHROOT_PATH /usr/bin/dnf -y --releasever=28 --forcearch=ppc64 --disablerepo=* --enablerepo=fedora --setopt=install_weak_deps=False --setopt=tsflags=nodocs groupinstall core base-x || umounts

# Install additional packages we want to have available in our live image
chroot $CHROOT_PATH /usr/bin/dnf -y --releasever=28 --forcearch=ppc64 --disablerepo=* --enablerepo=fedora --setopt=install_weak_deps=False --setopt=tsflags=nodocs install udisks2-zram bash-completion vim nano lynx chrony rsyslog wpa_supplicant openbox xterm feh || umounts
chroot $CHROOT_PATH /usr/bin/dnf clean all || umounts

# Additional configurations for the live session
cat >> $CHROOT_PATH/root/.bashrc << EOF || umounts

alias ll='ls -lh --color=auto'
alias lla='ls -lah --color=auto'
alias grep='grep --color=always'

PS1='\[\e[01;31m\]\h\[\e[01;34m\] \w $\[\e[00m\] '
EDITOR=vim
export PS1 EDITOR
EOF
cat >> $CHROOT_PATH/root/.bash_profile << EOF || umounts
feh --bg-fill /root/ps3linux-live-bg.jpg
exec startx
EOF
cat > $CHROOT_PATH/root/.xinitrc << EOF || umounts
source /etc/X11/xinit/xinitrc-common
exec openbox-session
EOF
cat > $CHROOT_PATH/usr/sbin/zram-swap.sh << EOF || umounts
#!/bin/bash

set -e

echo "lzo-rle" > /sys/block/zram0/comp_algorithm
echo 134217728 > /sys/block/zram0/disksize
mkswap /dev/zram0
swapon -p 100 /dev/zram0
EOF
cat > $CHROOT_PATH/etc/systemd/system/zram-swap.service << EOF || umounts
[Unit]
Description=ZRAM Swap Setup
DefaultDependencies=no
Before=swap.target
ConditionPathExists=/sys/block/zram0

[Service]
Type=oneshot
ExecStart=/usr/sbin/zram-swap.sh
RemainAfterExit=yes

[Install]
WantedBy=swap.target
EOF
cat > $CHROOT_PATH/etc/yum.repos.d/ps3linux.repo << EOF || umounts
[ps3linux]
name=PS3LINUX 1 - ppc64
failovermethod=priority
baseurl=https://ps3linux.net/ps3linux-repos/1/ppc64/
enabled=1
repo_gpgcheck=0
type=rpm
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-ps3linux-1-primary
EOF
cat > $CHROOT_PATH/etc/X11/xorg.conf << EOF || umounts
Section "ServerLayout"
    Identifier      "Layout0"
    Screen        0 "Screen0" 0 0
    InputDevice     "Mouse0" "CorePointer"
    InputDevice     "Keyboard0" "CoreKeyboard"
EndSection

Section "Files"
    ModulePath      "/usr/lib64/xorg/modules"
    FontPath        "built-ins"
EndSection

Section "Module"
    Load            "glx"
EndSection

Section "InputDevice"
    Identifier      "Keyboard0"
    Driver          "kbd"
EndSection

Section "InputDevice"
    Identifier      "Mouse0"
    Driver          "mouse"
    Option          "Protocol" "auto"
    Option          "Device" "/dev/input/mice"
    Option          "ZAxisMapping" "4 5 6 7"
EndSection

Section "Monitor"
    Identifier      "Monitor0"
    VendorName      "Monitor Vendor"
    ModelName       "Monitor Model"
EndSection

Section "Device"
    Identifier      "Card0"
    Driver          "fbdev"
EndSection

Section "Screen"
    Identifier      "Screen0"
    Device          "Card0"
EndSection

Section "ServerFlags"
    Option          "DefaultServerLayout" "Layout0"
    Option          "Xinerama" "0"
    Option          "OffTime" "0"
    Option          "BlankTime" "0"
    Option          "SuspendTime" "0"
    Option          "StandbyTime" "0"
EndSection
EOF
chroot $CHROOT_PATH /usr/bin/mkdir -pv /etc/systemd/system/getty@tty1.service.d || umounts
cat > $CHROOT_PATH/etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF || umounts
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I linux
EOF
cat > $CHROOT_PATH/etc/sysctl.d/98-ps3linux.conf << EOF || umounts
vm.stat_interval = 120
kernel.yama.ptrace_scope = 1
vm.min_free_kbytes = 4096
vm.watermark_scale_factor = 50
vm.vfs_cache_pressure = 150
net.core.rmem_max = 262144
net.core.wmem_max=262144
net.ipv4.tcp_rmem = 4096 65536 262144
EOF
cat >> $CHROOT_PATH/etc/motd << EOF || umounts
Run "ps3linux-install.sh --help" for install script info.

EOF
chroot $CHROOT_PATH /usr/bin/echo "ps3live" > $CHROOT_PATH/etc/hostname || umounts
chroot $CHROOT_PATH /usr/bin/echo "ps3vram" > $CHROOT_PATH/etc/modules-load.d/ps3vram.conf || umounts
chroot $CHROOT_PATH /usr/bin/echo 'KERNEL=="ps3vram", ACTION=="add", RUN+="/sbin/mkswap /dev/ps3vram", RUN+="/sbin/swapon -p 200 /dev/ps3vram"' > $CHROOT_PATH/etc/udev/rules.d/10-ps3vram.rules || umounts
chroot $CHROOT_PATH /usr/bin/sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config || umounts
chroot $CHROOT_PATH /usr/bin/ln -sfv RPM-GPG-KEY-fedora-28-primary /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-primary || umounts
chroot $CHROOT_PATH /usr/bin/rm -fv $CHROOT_PATH/etc/nsswitch.conf.{rpmnew,bak} $CHROOT_PATH/etc/yum.repos.d/*.rpmnew || umounts
chroot $CHROOT_PATH /usr/bin/mkdir -pv /mnt/target || umounts
chroot $CHROOT_PATH /usr/bin/chmod 0755 /usr/sbin/zram-swap.sh || umounts
cp -fv $RESOURCES_PATH/RPM-GPG-KEY-ps3linux-1-primary $CHROOT_PATH/etc/pki/rpm-gpg/RPM-GPG-KEY-ps3linux-1-primary || umounts
cp -fv $RESOURCES_PATH/motd $CHROOT_PATH/etc/motd || umounts
cp -fv $RESOURCES_PATH/ps3linux-install.sh $CHROOT_PATH/usr/sbin/ps3linux-install.sh || umounts
cp -fv $RESOURCES_PATH/ps3linux-live-bg.jpg $CHROOT_PATH/root/ps3linux-live-bg.jpg || umounts
chroot $CHROOT_PATH /usr/bin/systemctl set-default multi-user.target || umounts
chroot $CHROOT_PATH /usr/bin/systemctl disable auditd.service || umounts
chroot $CHROOT_PATH /usr/bin/systemctl disable dnf-makecache.timer || umounts
chroot $CHROOT_PATH /usr/bin/systemctl disable fedora-import-state.service || umounts
chroot $CHROOT_PATH /usr/bin/systemctl disable fedora-readonly.service || umounts
chroot $CHROOT_PATH /usr/bin/systemctl disable firewalld.service || umounts
chroot $CHROOT_PATH /usr/bin/systemctl disable mdmonitor.service || umounts
chroot $CHROOT_PATH /usr/bin/systemctl disable multipathd.service || umounts
chroot $CHROOT_PATH /usr/bin/systemctl disable sssd-secrets.socket || umounts
chroot $CHROOT_PATH /usr/bin/systemctl disable sssd.service || umounts
chroot $CHROOT_PATH /usr/bin/systemctl enable zram-swap.service || umounts

# Unmount virtual filesystems from our ppc64 chroot
umount -v $CHROOT_PATH/tmp
umount -v $CHROOT_PATH/run
umount -v $CHROOT_PATH/dev/pts
umount -v $CHROOT_PATH/dev
umount -v $CHROOT_PATH/sys
umount -v $CHROOT_PATH/proc

# Remove stuff the live ISO doesn't need
rm -rvf $CHROOT_PATH/usr/share/doc
rm -rvf $CHROOT_PATH/usr/share/man
rm -rvf $CHROOT_PATH/lib/firmware/*

# Strip all binary and library files and delete all static libs
find $CHROOT_PATH -type f \( -perm -111 -o -name '*.so*' -o -name '*.ko' \) -exec file {} \; | grep 'ELF' | cut -d: -f1 | while read f; do echo "Stripping $f"; powerpc64-linux-gnu-strip --strip-unneeded "$f" || true; done
find $CHROOT_PATH/usr/lib64 -name '*.a' -delete

# Build an initramfs image to handle mounting squashfs root and setup overlayfs
mkdir -pv $INITRAMFS_PATH/{dev,iso,lower,mnt,proc,run,sys,sysroot/{dev,proc,run,sys,tmp},tmp,usr/{bin,lib,lib64,sbin},upper/{upper,work}}
pushd $INITRAMFS_PATH
ln -sv usr/bin bin
ln -sv usr/lib lib
ln -sv usr/lib64 lib64
ln -sv usr/sbin sbin
popd
mknod -m 600 $INITRAMFS_PATH/dev/console c 5 1
mknod -m 666 $INITRAMFS_PATH/dev/null c 1 3

# Copy kernel module(s) from our kernel build into initramfs and chroot directories
mkdir -pv $INITRAMFS_PATH/lib/modules
cp -rvf $(pwd)/kmods/lib/modules/$KVER $INITRAMFS_PATH/lib/modules/
rm $INITRAMFS_PATH/lib/modules/$KVER/build
cp -rvf $(pwd)/kmods/lib/modules/$KVER $CHROOT_PATH/lib/modules/
rm $CHROOT_PATH/lib/modules/$KVER/build

# Copy in our custom minimal init script
cp -fv $RESOURCES_PATH/init $INITRAMFS_PATH/

# Copy some bins and their dependent libs from our previously built ppc64 chroot directory
cp -fv $CHROOT_PATH/usr/bin/mount $INITRAMFS_PATH/usr/bin/mount
cp -fv $CHROOT_PATH/usr/bin/sleep $INITRAMFS_PATH/usr/bin/sleep
cp -fv $CHROOT_PATH/usr/bin/echo $INITRAMFS_PATH/usr/bin/echo
cp -fv $CHROOT_PATH/usr/bin/mkdir $INITRAMFS_PATH/usr/bin/mkdir
cp -fv $CHROOT_PATH/usr/sbin/switch_root $INITRAMFS_PATH/usr/sbin/switch_root
cp -fv $CHROOT_PATH/usr/bin/bash $INITRAMFS_PATH/usr/bin/bash
cp -fv $CHROOT_PATH/lib64/libmount.so.1.1.0 $INITRAMFS_PATH/lib64/libmount.so.1.1.0
cp -fv $CHROOT_PATH/lib64/libblkid.so.1.1.0 $INITRAMFS_PATH/lib64/libblkid.so.1.1.0
cp -fv $CHROOT_PATH/lib64/libuuid.so.1.3.0 $INITRAMFS_PATH/lib64/libuuid.so.1.3.0
cp -fv $CHROOT_PATH/lib64/librt-2.27.so $INITRAMFS_PATH/lib64/librt-2.27.so
cp -fv $CHROOT_PATH/lib64/libselinux.so.1 $INITRAMFS_PATH/lib64/libselinux.so.1
cp -fv $CHROOT_PATH/lib64/libc-2.27.so $INITRAMFS_PATH/lib64/libc-2.27.so
cp -fv $CHROOT_PATH/lib64/ld-2.27.so $INITRAMFS_PATH/lib64/ld-2.27.so
cp -fv $CHROOT_PATH/lib64/libpthread-2.27.so $INITRAMFS_PATH/lib64/libpthread-2.27.so
cp -fv $CHROOT_PATH/lib64/libpcre2-8.so.0.7.0 $INITRAMFS_PATH/lib64/libpcre2-8.so.0.7.0
cp -fv $CHROOT_PATH/lib64/libdl-2.27.so $INITRAMFS_PATH/lib64/libdl-2.27.so
cp -fv $CHROOT_PATH/lib64/libtinfo.so.6.1 $INITRAMFS_PATH/lib64/libtinfo.so.6.1
pushd $INITRAMFS_PATH/usr/bin
ln -s bash sh
popd

# Create necessary library symlinks
pushd $INITRAMFS_PATH/lib64
ln -sv libmount.so.1.1.0 libmount.so.1
ln -sv libblkid.so.1.1.0 libblkid.so.1
ln -sv libuuid.so.1.3.0 libuuid.so.1
ln -sv librt-2.27.so librt.so.1
ln -sv libc-2.27.so libc.so.6
ln -sv ld-2.27.so ld64.so.1
ln -sv libpthread-2.27.so libpthread.so.0
ln -sv libpcre2-8.so.0.7.0 libpcre2-8.so.0
ln -sv libdl-2.27.so libdl.so.2
ln -sv libtinfo.so.6.1 libtinfo.so.6
popd

# Create directory that will become our finished live ISO
mkdir -pv $LIVE_ISO_PATH/{boot,etc,LiveOS}

# Compress initramfs and output to final live ISO directory
pushd $INITRAMFS_PATH
find . | cpio -H newc -o | gzip > $LIVE_ISO_PATH/boot/initramfs.img
popd

# Copy kernel and yaboot.conf files to final live ISO directories
cp -fv $(pwd)/linux-$KVER/arch/powerpc/boot/zImage $LIVE_ISO_PATH/boot/vmlinuz
cp -fv $RESOURCES_PATH/yaboot.conf $LIVE_ISO_PATH/etc/yaboot.conf

# Set root password to 'HACKTHEPLANET'
chmod 600 $CHROOT_PATH/etc/shadow
sed -i "s|^root:[^:]*|root:$5$P2HqYazrcar/5I95$75cOCMa6pH1kSCznAFQc0N4V.DGvgf2nxUvHyF0Uib.|" $CHROOT_PATH/etc/shadow
chmod 000 $CHROOT_PATH/etc/shadow

# Master ISO file from our live ISO directory
mksquashfs $CHROOT_PATH $LIVE_ISO_PATH/LiveOS/liveroot.img -comp xz -b 1M -Xdict-size 100% -noappend
mkisofs -r -J -V PS3LIVE -o PS3LINUX_Live_ISO.iso $LIVE_ISO_PATH

# Remove directoies used during the build - keep $CHROOT_PATH if requested
rm -fv $(pwd)/linux-$KVER.tar.xz
rm -rfv $(pwd)/kmods $(pwd)/linux-$KVER $INITRAMFS_PATH $LIVE_ISO_PATH
if [ "$KEEP" -eq 0 ]; then
    rm -rfv $CHROOT_PATH
fi

echo ""
echo "Done."
echo "Live ISO image is PS3LINUX_Live_ISO.iso."
echo ""

exit 0

