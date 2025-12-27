#!/bin/bash

set -e

ZRAM_DEV=zram0
PRIORITY=100
MEM_TOTAL_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
ZRAM_SIZE_BYTES=$((MEM_TOTAL_KB * 1024 / 2))

echo lz4 > /sys/block/${ZRAM_DEV}/comp_algorithm
echo ${ZRAM_SIZE_BYTES} > /sys/block/${ZRAM_DEV}/disksize
mkswap /dev/${ZRAM_DEV}
swapon -p ${PRIORITY} /dev/${ZRAM_DEV}

