#!/bin/sh

set -euo pipefail

[ $(id -u) -eq 0 ] || exit 1

CHROOT_PATH=$(pwd)/PS3LINUX_ppc64_chroot

sed -i 's@exec startx@@g' $CHROOT_PATH/root/.bash_profile
sed -i 's@feh --bg-fill /root/ps3linux-live-bg.jpg@@g' $CHROOT_PATH/root/.bash_profile
mount -vt proc /proc $CHROOT_PATH/proc
mount -vt sysfs /sys $CHROOT_PATH/sys
mount -vo bind /dev $CHROOT_PATH/dev
mount -vo bind /dev/pts $CHROOT_PATH/dev/pts
mount -vt tmpfs tmpfs $CHROOT_PATH/run
mount -vt tmpfs tmpfs $CHROOT_PATH/tmp
/bin/bash -c "chroot $CHROOT_PATH /usr/bin/env -i ARCH=powerpc HOME=/root TERM=$TERM PS1='\u:\w\$ ' PATH=/root/.local/bin:/usr/lib64/ccache:/usr/bin:/usr/sbin:/bin:/sbin /bin/bash --login"
umount -v $CHROOT_PATH/tmp
umount -v $CHROOT_PATH/run
umount -v $CHROOT_PATH/dev/pts
umount -v $CHROOT_PATH/dev
umount -v $CHROOT_PATH/sys
umount -v $CHROOT_PATH/proc

