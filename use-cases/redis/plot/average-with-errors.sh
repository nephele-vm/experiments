#!/bin/bash

MYDIR="$1"
if [ ! -d $MYDIR ]; then
	echo "Usage: $0 <files-directory>"
	exit 1
fi

get_average_on_column() {
	local myfile="$1"
	local column="$2"

	cat $myfile  | cut -d';' -f$column | awk -F  ";" '
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
	printf "%.6f,%.6f,%.6f", avg,  min, max
}
' || echo $myfile
}

get_average_2nd_fork_and_save() {
	local myfile="$1"
	local size="$(basename $(echo $myfile | sed 's|\(.*\)/[^/]\+|\1|g'))"
	printf "%d," $size
	get_average_on_column $myfile 4
	printf ","
	get_average_on_column $myfile 5
	printf "\n"
}

get_average_userspace() {
	local myfile="$1"
	get_average_on_column $myfile 2
	printf "\n"
}

iterate_sizes() {
	local mydir="$1"
	local output_file="$mydir/average"
	local what="$(basename $mydir)"

	truncate -s 0 $output_file 

	for f in $(find $mydir -mindepth 1 -maxdepth 1 -type d | sort -n -k 4,4 -t'/'); do
		local input_file="$f/children"
		local output_file_fork="$output_file.fork"
		get_average_2nd_fork_and_save $input_file >> $output_file_fork

		if [ "$what" = "vm" ]; then
			local input_file="$f/breakdown"
			local output_file_userspace="$output_file.userspace"
			get_average_userspace $input_file >> $output_file_userspace

			paste -d ',' $output_file_fork $output_file_userspace >> $output_file 
			rm $output_file_fork $output_file_userspace
		else
			cat $output_file_fork >> $output_file
			rm $output_file_fork
		fi
	done
}

mydir="$1"
mydir=${mydir%"/"}

mysubdir="$mydir/process"
if [ ! -d $mysubdir ]; then
	echo "Directory does not contain process subdir."
	exit -2
fi
iterate_sizes $mysubdir

mysubdir="$mydir/vm"
if [ ! -d $mysubdir ]; then
	echo "Directory does not contain vm subdir."
	exit -2
fi
iterate_sizes $mysubdir

