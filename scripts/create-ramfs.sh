#!/bin/bash -e

if [ $# -ne 2 ]; then
	echo "Usage: $0 <rootfs-path> <out-initramfs-path>"
	exit 2
fi

MYROOTFS="$1"
MYFILE="$2"

pushd $MYROOTFS >/dev/null
find -depth -print | tac | cpio -ov --format newc > $MYFILE
# cpio -itv < $MYFILE
popd &>/dev/null

