#!/bin/bash

# pin and change prio for Qemu backend process
parent_domid=$(xl list | head -n 3 | tail -n 1 | tr -s ' ' | cut -d' ' -f2)
qemu_pid_arr=$(ps -T -o tid,cmd $(pgrep qemu) | grep "xen-domid $parent_domid" | grep -v grep | sed 's/^ *//g' | cut -d' ' -f1)

#CPUID=10-13
HOSTNAME="$(hostname)"
if [ $HOSTNAME = "computer2" ]; then
	CPUID=10-13
elif [ $HOSTNAME = "computer10" ]; then
	CPUID=1
elif [ $HOSTNAME = "c428" ]; then
	CPUID=1
elif [ $HOSTNAME = "c429" ]; then
	CPUID=1
fi
for id in ${qemu_pid_arr[@]}; do
	taskset --cpu-list -p $CPUID $id &>/dev/null
done
sleep 3; ps -T -eo pid,tid,psr,cmd | grep qemu | grep "xen-domid $parent_domid" | grep -v grep
renice -n -20 -p $qemu_pid

# change weight for child domain
#child_domid=$(xl list | tail -n 1 | tr -s ' ' | cut -d' ' -f2)
#xl sched-credit2 -d $child_domid -w 512
