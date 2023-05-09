#!/bin/bash

FILES_DIR="$1"
BOOT_CSV_FILE="$FILES_DIR/dom0-mem-consumption-boot.csv"
CLONE_CSV_FILE="$FILES_DIR/dom0-mem-consumption-clone.csv"
OUTPUT_FILE="$FILES_DIR/dom0-mem-consumption.pdf"

SCRIPT_DIR="$(dirname $0)"

gnuplot -e "filename1='$BOOT_CSV_FILE' ; filename2='$CLONE_CSV_FILE' ; output1='$OUTPUT_FILE'" "$SCRIPT_DIR/dom0-mem-consumption-aggregated.gnu"

