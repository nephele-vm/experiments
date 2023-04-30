#!/bin/bash

DATA_FILE="$1"
BATCH="${2:-35}"

SCRIPT_DIR="$(dirname $0)"
EXPERIMENT_ROOT_DIR="$(realpath $SCRIPT_DIR/..)"

TOTAL=0
MAX=$(cat $DATA_FILE | wc -l)
while [ $TOTAL -lt $MAX ]; do
	i=0
	while [ $i -lt $BATCH ]; do
		read line
		[ -z "$line" ] && exit
		i=$(($i + 1))
		echo $line
	done | $EXPERIMENT_ROOT_DIR/process/redis-cli -h 10.8.0.2 --pipe &>/dev/null
	#done | $SCRIPT_DIR/print-batch.sh
	TOTAL=$(($TOTAL + $BATCH))
#	echo "$TOTAL"
done < $DATA_FILE
