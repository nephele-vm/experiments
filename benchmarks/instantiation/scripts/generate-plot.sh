#!/bin/bash

MYDIR="$1"

SCRIPT_DIR="$(dirname $0)"
OUTPUT=$MYDIR/boot-vs-clone-vs-save-restore.pdf

gnuplot -e "filename1='$MYDIR/boot/xl.csv' ; filename2='$MYDIR/save-restore/xl.csv' ; filename3='$MYDIR/clone-1-by-1/deep-copy/xl.csv' ; filename4='$MYDIR/clone-1-by-1/xl.csv' ; output1='$OUTPUT'" $SCRIPT_DIR/plot-boot-vs-clone-vs-save-restore.gnu && evince $OUTPUT &>/dev/null &

