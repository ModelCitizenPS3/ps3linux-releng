#!/bin/sh

set -euo pipefail

[ $(id -u) -eq 0 ] || exit 1

CHROOT_PATH=$(pwd)/PS3LINUX_ppc64_chroot_kept

mount -t proc /proc $CHROOT_PATH/proc
mount -t sysfs /sys $CHROOT_PATH/sys
mount -o bind /dev $CHROOT_PATH/dev
mount -o bind /dev/pts $CHROOT_PATH/dev/pts
mount -t tmpfs tmpfs $CHROOT_PATH/run
mount -t tmpfs tmpfs $CHROOT_PATH/tmp
/bin/bash -c "chroot $CHROOT_PATH /usr/bin/env -i ARCH=powerpc HOME=/root TERM=$TERM PS1='\u:\w\$ ' PATH=/root/.local/bin:/usr/lib64/ccache:/usr/bin:/usr/sbin:/bin:/sbin /bin/bash --login"
umount $CHROOT_PATH/tmp
umount $CHROOT_PATH/run
umount $CHROOT_PATH/dev/pts
umount $CHROOT_PATH/dev
umount $CHROOT_PATH/sys
umount $CHROOT_PATH/proc

