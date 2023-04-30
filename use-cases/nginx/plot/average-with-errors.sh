#!/bin/bash

MYDIR="$1"
if [ ! -d $MYDIR ]; then
	echo "Usage: $0 <files-directory>"
	exit 1
fi

get_average() {
	local myfile="$1"
	#tr -s ' ' < $myfile  | cut -d' ' -f2 | awk '{ total += $1; count++ } END { print total/count }'
	echo -ne $myfile | sed 's/.*\([0-9]\+\)$/\1/g'
	tr -s ' ' < $myfile  | cut -d' ' -f2 | awk '
NR == 1 {
	total = $1
	min = $1
	max = $1
} 
NR > 1 {
	total += $1
	if ( $1 > max ) {
		max = $1
	}
	if ( $1 < min ) {
		min = $1
	}
}
END {
	avg = total / NR
	print "," avg "," min "," max
}
'
}

FILE1="$MYDIR/workers-1"
FILE2="$MYDIR/workers-2"
FILE3="$MYDIR/workers-3"
FILE4="$MYDIR/workers-4"
FILE5="$MYDIR/workers-5"

OUTPUT="$MYDIR/workers-average"
truncate -s 0 $OUTPUT 

get_average $FILE1 >> $OUTPUT
get_average $FILE2 >> $OUTPUT
get_average $FILE3 >> $OUTPUT
get_average $FILE4 >> $OUTPUT

