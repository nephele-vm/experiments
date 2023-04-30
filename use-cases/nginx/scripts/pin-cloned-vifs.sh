#!/bin/bash

# we skip first 2 vifs of master

i=1
while read pid; do
	m=$(($i % 8))
	if   [ $m -eq 1 -o $m -eq 2 ]; then
		taskset -p 0x10 $pid >/dev/null
	elif [ $m -eq 3 -o $m -eq 4 ]; then
		taskset -p 0x20 $pid >/dev/null
	elif [ $m -eq 5 -o $m -eq 6 ]; then
		taskset -p 0x40 $pid >/dev/null
	elif [ $m -eq 7 -o $m -eq 0 ]; then
		taskset -p 0x80 $pid >/dev/null
	fi
	i=$((i + 1))
done < <(ps -eTo cmd,pid | grep -e '\[vif' | grep -v grep | tail -n +3 | tr -s ' ' | cut -d' ' -f2)
