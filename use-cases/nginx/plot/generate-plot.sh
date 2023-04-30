#!/bin/bash

DATA_DIR="$1"
if [ ! -d "$DATA_DIR" ]; then
	echo "Directory does not exist: $DATA_DIR"
	exit 2
fi

PROCESS_DATA_DIR="$DATA_DIR/process"
if [ ! -d "$PROCESS_DATA_DIR" ]; then
	echo "Directory does not exist: $PROCESS_DATA_DIR"
	exit 2
fi

CLONES_DATA_DIR="$DATA_DIR/clones"
if [ ! -d "$CLONES_DATA_DIR" ]; then
	echo "Directory does not exist: $CLONES_DATA_DIR"
	exit 2
fi


SCRIPT_DIR="$(dirname $0)"

$SCRIPT_DIR/average-with-errors.sh $PROCESS_DATA_DIR 
$SCRIPT_DIR/average-with-errors.sh $CLONES_DATA_DIR 

gnuplot -e "filename1='$PROCESS_DATA_DIR/workers-average' ; filename2='$CLONES_DATA_DIR/workers-average' ; output1='$DATA_DIR/wrk-nopolling-bars.pdf'" "$SCRIPT_DIR/wrk-nopolling-bars.gnu"

