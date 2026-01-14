#!/bin/sh

set -euo pipefail

[ $(id -u) -eq 0 ] || exit 1

CHROOT_PATH=$(pwd)/PS3LINUX_chroot
LIVE_ISO_PATH=$(pwd)/PS3LINUX_LIVE_ISO

[ -d $LIVE_ISO_PATH ] && rm -rf $LIVE_ISO_PATH
mkdir -p $LIVE_ISO_PATH/{boot,etc,LiveOS}
mksquashfs $CHROOT_PATH $LIVE_ISO_PATH/LiveOS/ps3_install.img -comp xz -b 1M -Xdict-size 100% -noappend
[ -d $(pwd)/resources/initramfs/lib/modules/6.0.19 ] && rm -rf $(pwd)/resources/initramfs/lib/modules/6.0.19
mkdir -p $(pwd)/resources/initramfs/lib/modules
cp -r $(pwd)/resources/6.0.19 $(pwd)/resources/initramfs/lib/modules/
pushd $(pwd)/resources/initramfs
./rd_gen.sh
popd
[ -f $LIVE_ISO_PATH/boot/initramfs.img ] && rm $LIVE_ISO_PATH/boot/initramfs.img
mv $(pwd)/resources/initramfs.img $LIVE_ISO_PATH/boot/initramfs.img
cp $(pwd)/resources/vmlinuz $LIVE_ISO_PATH/boot/vmlinuz
cat > $LIVE_ISO_PATH/etc/yaboot.conf << EOF
image=/boot/vmlinuz
    label=PS3LINUX
    read-only
    initrd=/boot/initramfs.img
    append="video=ps3fb:mode:1667 selinux=0 audit=0"
EOF
[ -f $LIVE_ISO_PATH.iso ] && rm $LIVE_ISO_PATH.iso
mkisofs -r -J -V PS3LINUX -o $LIVE_ISO_PATH.iso $LIVE_ISO_PATH

