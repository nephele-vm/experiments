#!/bin/bash
#set -e

MAX_VM_CONNECTIONS=64
MIN_WORKERS=1
#MAX_WORKERS=4
MAX_WORKERS=1

WRK_DURATION_SEC=5

HOSTNAME="$(hostname)"
if [ $HOSTNAME = "computer2" ]; then 
	WRK_MASK_4_WORKERS=0x1f00
	WRK_MASK_5_WORKERS=0x1f00 #TODO

elif [ $HOSTNAME = "computer10" ]; then 
	WRK_MASK_4_WORKERS=0x000f
	WRK_MASK_5_WORKERS=0x000f
fi
WRK_MASK=$WRK_MASK_4_WORKERS

ARPING_INTERVAL_SEC=$((2 * 60))

SCRIPT_DIR="$(dirname $0)"
EXPERIMENT_DIR="$(realpath $SCRIPT_DIR/..)"

ROOTFS="$EXPERIMENT_DIR/rootfs"
CONFIG_FILE="$ROOTFS/nginx/conf/worker_process.conf"
RESULTS_DIR="$EXPERIMENT_DIR/results/wrk/01"
[ ! -d $RESULTS_DIR ] && mkdir -p $RESULTS_DIR

if [ -f /sys/hypervisor/uuid ]; then
	START_PROCESS=0
else
	START_PROCESS=1
fi

write_nginx_config() {
	local workers_num="$1"
	truncate -s 0 $CONFIG_FILE
	echo "worker_processes $workers_num;" >> $CONFIG_FILE 
	echo "master_process on;"  >> $CONFIG_FILE
}

run_experiment() {
	local workers_num="$1"
	local results_file="$RESULTS_DIR/workers-$i"

	# update config file with new workers number
	write_nginx_config $workers_num 


	if [ $START_PROCESS -eq 1 ]; then
		# start nginx
		killall nginx &>/dev/null
		sleep 3
		nginx -c $ROOTFS/nginx/conf/nginx.conf &
		sleep 3

		if [ $HOSTNAME = "computer2" ]; then 
			CPU=14

		elif [ $HOSTNAME = "computer10" ]; then 
			CPU=1
		fi

		while read pid; do
			taskset --cpu-list -p $CPU $pid
			CPU=$((CPU + 1))
		done < <(pgrep nginx)

		TARGET_IP="10.8.0.1"
	else
		# generate ramfs
		/root/images/unikraft/scripts/create-ramfs.sh $ROOTFS $EXPERIMENT_DIR/initramfs.cpio

		# start nginx
		$SCRIPT_DIR/start-nginx-with-clones.sh

		TARGET_IP="10.8.0.2"
	fi

	SINCE_LAST_ARPING_SEC=0

	WHOLE_SESSION=0
	if [ $WHOLE_SESSION -eq 1 ]; then
		# create at least $MAX_WORKERS connections
		CONN_MIN=$MAX_WORKERS
		CONN_MAX=$MAX_CONNECTIONS
		CONN_INC=1
		REPETITIONS=1
	else
		CONN_MIN=400
		CONN_MAX=400
		CONN_INC=1
		REPETITIONS=30
		#REPETITIONS=5
	fi
	for i in $(seq $CONN_MIN $CONN_INC $CONN_MAX); do
		for r in $(seq $REPETITIONS); do
			echo -ne "$i;"
			chrt -r 1 taskset $WRK_MASK wrk -t$MAX_WORKERS -c$i -d${WRK_DURATION_SEC}s http://$TARGET_IP/index.html | grep '^Requests'

			if [ $START_PROCESS -eq 1 ]; then
				# refresh ARP entries
				SINCE_LAST_ARPING_SEC=$(($SINCE_LAST_ARPING_SEC + $WRK_DURATION_SEC))
				if [ $SINCE_LAST_ARPING_SEC -ge $ARPING_INTERVAL_SEC ]; then
					$SCRIPT_DIR/arping-vifs.sh
					SINCE_LAST_ARPING_SEC=0
				fi
			fi
		done
	done > $results_file
}

MAX_CONNECTIONS=$(($MAX_VM_CONNECTIONS * $MAX_WORKERS))
for i in $(seq $MIN_WORKERS $MAX_WORKERS); do
	echo "workers=$i"
	run_experiment $i
done

