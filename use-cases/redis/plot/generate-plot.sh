#!/bin/bash

MYDIR="$1"

SCRIPT_DIR="$(dirname $0)"

$SCRIPT_DIR/average-with-errors.sh $MYDIR
echo "Process:"
cat $MYDIR/process/average
echo "VM:"
cat $MYDIR/vm/average

$SCRIPT_DIR/bars.py $MYDIR && evince $MYDIR/bars.py.pdf &

