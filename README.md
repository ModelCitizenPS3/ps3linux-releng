# PS3LINUX Release Engineering

For now this is just a place for me to store what "scripts" and configs I use for building live Linux media that boots from the petitboot bootloader. PS3LINUX is a fork of Fedora 28 (ppc64) with optimizations for the PS3 and any updates I package and serve from my personal rpm repo hosted here: [http://www.ps3linux.net/ps3linux-repos/](http://www.ps3linux.net/ps3linux-repos).

If you are interested in developing for PS3LINUX but do not have a dedicated Linux PS3 like I do, then this is the place you want to be. My `PS3LINUX_live_iso_gen.sh` script creates two directories you can chroot into for developing rpm packages for PS3LINUX: FC28-x86_64_chroot and PS3LINUX_chroot. PS3LINUX_chroot is a vanilla Fedora 28 ppc64 environment and FC28-x86_64_chroot is a Fedora 28 x86_64 environment that can be used for cross compiling kernel packages (which is much faster than building kernels in the ppc64 chroot).

### Dependencies

1. a Fedora operating system - my scripts are heavily dependent on the dnf package manager
2. qemu - for running programs executed within a ppc64 chroot  `sudo dnf install qemu`
3. enable systemd's proc-sys-fs-binfmt_misc.mount unit:  `sudo systemctl enable proc-sys-fs-binfmt_misc.mount`
4. optional - add your user to the kvm group:  `sudo usermod -aG kvm <USERNAME>`
5. iso mastering utils (mksquashfs, mkisofs, etc):  `sudo dnf install squashfs-tools genisoimage xorriso`

### How to use

NOTE - All the scripts in the toplevel directory are meant to be run as root and will fail/exit if run without root privileges.

1. clone this repo:  `git clone https://github.com/ModelCitizenPS3/ps3linux-releng.git`
2. enter repo directory:  `cd ps3linux-releng`
3. run script:  `sudo ./PS3LINUX_live_iso_gen.sh`
5. you should now have the file `PS3LINUX_Live_ISO.iso`
6. burn the image to a USB or CD/DVD:  `sudo dd if=PS3LINUX_LIVE_ISO.iso of=<USB DEVICE>` - USB device will be something like `/dev/sda`
7. BE CAREFUL WITH THE DD COMMAND. Double check that you set `of` (output file) correctly!
8. insert USB in your PS3 and boot `PS3LIVE` from your petitboot bootloader menu
9. login as root - password is `HACKTHEPLANET`
10. do system maintenance/recovery tasks or install an OS like Gentoo or Adelie if you'd like

Try out my PS3LINUX install script by running `ps3linux-install.sh` as root.

Note: I realize my "scripts" are ugly and my bash is basic. I do intend to clean the scripts up a bit, add comments, and add some logic to make them more dynamic and robust.

## THE MODEL CITIZEN
