#!/bin/bash

if [ -z "$1" -o ! -d "$1" ]; then
	echo "Usage: $0 <results-dir>"
	exit 2
fi

RESULTS_DIR="$1"
OUTPUT_FILE="$RESULTS_DIR/out.pdf"

FILENAME_PARAM=""
FILENAME_PARAM="$FILENAME_PARAM  filename1='$RESULTS_DIR/results.unikraft.no-cloning.baseline'"
FILENAME_PARAM="$FILENAME_PARAM; filename2='$RESULTS_DIR/results.unikraft.no-cloning'"
FILENAME_PARAM="$FILENAME_PARAM; filename3='$RESULTS_DIR/results.unikraft.cloning.baseline'"
FILENAME_PARAM="$FILENAME_PARAM; filename4='$RESULTS_DIR/results.unikraft.cloning'"
FILENAME_PARAM="$FILENAME_PARAM; filename5='$RESULTS_DIR/results.linux.app.baseline'"
FILENAME_PARAM="$FILENAME_PARAM; filename6='$RESULTS_DIR/results.linux.app'"
FILENAME_PARAM="$FILENAME_PARAM; filename7='$RESULTS_DIR/results.linux.module'"

gnuplot -e "$FILENAME_PARAM ; output1='$OUTPUT_FILE'" plot.gnu

evince $OUTPUT_FILE &
