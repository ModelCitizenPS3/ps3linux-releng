#!/bin/sh

find . | cpio -H newc -o | gzip > ../initramfs.img

