#!/bin/bash
#set -e

SKIP_PROCESS=0
SKIP_VM=0

if [ ! -z "$1" ]; then
	REPETITIONS="$1"
	if [ "$2" = "process" ]; then
		SKIP_VM=1
	elif [ "$2" = "vm" ]; then
		SKIP_PROCESS=1
	fi
else
	REPETITIONS=3
fi

HOSTNAME="$(hostname)"

SCRIPT_DIR="$(dirname $0)"

EXPERIMENT_ROOT_DIR="$(realpath $SCRIPT_DIR/..)"
REDIS_SRV="$EXPERIMENT_ROOT_DIR/process/redis-server"
REDIS_CLI="$EXPERIMENT_ROOT_DIR/process/redis-cli"
XL_CFG="$EXPERIMENT_ROOT_DIR/config-redis-$HOSTNAME"
XL_CFG_TMPL="$EXPERIMENT_ROOT_DIR/config-redis.tmpl"
XL_CFG_GENERATED="$EXPERIMENT_ROOT_DIR/config-redis.generated"
ROOTFS="$EXPERIMENT_ROOT_DIR/rootfs"
DATA_FILE="$EXPERIMENT_ROOT_DIR/data.txt"

GUESTS_LOG_DIR="/var/log/xen/guest"
[ ! -d $GUESTS_LOG_DIR ] && mkdir -p $GUESTS_LOG_DIR

TRACE_LABEL="REDIS_TRACE"

recreate_dir() {
	local mydir="$1"
	[ -d $mydir ] && rm -fr $mydir
	mkdir -p $mydir
}

RESULTS_DIR="$EXPERIMENT_ROOT_DIR/results/v01"
[ ! -d $RESULTS_DIR ] && mkdir -p $RESULTS_DIR
RESULTS_VM_DIR="$RESULTS_DIR/vm"
recreate_dir $RESULTS_VM_DIR
RESULTS_PROCESS_DIR="$RESULTS_DIR/process"
recreate_dir $RESULTS_PROCESS_DIR
REDIS_LOG="/tmp/redis.log"

XENCLONED_LOG="/root/xencloned.log"
#BREAKDOWN_RESULTS="$RESULTS_VM_DIR/breakdown"


generate_mass_data() {
	local kv_num="$1"
	echo "Generating data.."
	truncate -s 0 $DATA_FILE
	i=0
	while [ $i -lt $kv_num ]; do
		#echo "SET Key$i Value$i"
		printf "SET %016d %016d\n" $i $i
		i=$((i + 1))
	done > $DATA_FILE
}

write_results_pair() {
	local what="$1"
	local input="$2"
	local output="$3"
	while read firstval; do
		read secondval
		echo "$firstval;$secondval"
	done < <(grep $TRACE_LABEL $input | grep "$what" | tr -s ' ' | cut -d' ' -f2) >> $output
}

write_results_process() {
	local who="$1"
	local input="$2"
	local output="$3"
	grep $TRACE_LABEL $input | grep "$who" | tr -s ' ' | cut -d' ' -f2 > $output
}

collect_results_process() {
	local kv_num="$1"
	local logfile="$RESULTS_PROCESS_DIR/snapshot-$kv_num"
	local results_dir="$RESULTS_PROCESS_DIR/$kv_num"

	# get parent results from process log
	write_results_pair "fork parent" $logfile $results_dir/parent

	# get children results from process log
	write_results_process "fork child" $logfile $results_dir/fork-child
	write_results_process "save" $logfile $results_dir/save
	write_results_process "total" $logfile $results_dir/total
	paste -d ';' $results_dir/fork-child $results_dir/save $results_dir/total > $results_dir/children.tmp
	rm $results_dir/fork-child $results_dir/save $results_dir/total
	# each entry has 'fork;save;total' for 1st and 2nd fork respectively
	while read firstval; do
		read secondval
		echo "$firstval;$secondval"
	done < $results_dir/children.tmp > $results_dir/children
	rm $results_dir/children.tmp

}

write_results_vm_child() {
	local input="$1"
	local output="$2"
	grep $TRACE_LABEL $input | tr -s ' ' | cut -d' ' -f2 | tr '\n' ';' >> $output
}

collect_results_vm() {
	local kv_num="$1"
	local repetitions="$2"
	local name=$(grep '^name *=' $XL_CFG | sed 's/^name *= *"\(.\+\)"/\1/g')
	local results_dir="$RESULTS_VM_DIR/$kv_num"

	# get parent results from guest log
	local parent_log="$GUESTS_LOG_DIR/guest-$name.log"
	write_results_pair "fork parent" $parent_log $results_dir/parent
	rm $parent_log

	# get children results from guests logs
	local results_children="$results_dir/children"
	for f in $(find $GUESTS_LOG_DIR -name "guest-$name-child-*.log" | sort); do
		write_results_vm_child $f $results_children
		rm $f
	done
	echo >> $results_children
}

SLEEP_SEC=2

do_single_snapshot() {
	echo BGSAVE | $REDIS_CLI -h $TARGET_IP --pipe &>/dev/null
	sleep $SLEEP_SEC #TODO

#	if [ $VM_ROUND -eq 1 ]; then
#		last_vif=$(ip l show | grep -o 'vif[0-9]\+.[0-9]\+' | tail -n 1)
#		ip link set $last_vif nomaster
#	fi

	# update userspace results for VMs
	if [ $VM_ROUND -eq 1 ]; then
		userspace=$(tail -n 1 $XENCLONED_LOG | grep -o "msec=.*" | cut -d'=' -f2)
		echo -ne "$userspace;" >> $BREAKDOWN_RESULTS
	fi
}


VM_ROUND=0
do_snapshots() {
	COMMANDS_NUM=1
	for r in $(seq $COMMANDS_NUM); do
		do_single_snapshot

		if [ $VM_ROUND -eq 1 ]; then
			echo >> $BREAKDOWN_RESULTS
		fi
	done
	echo SHUTDOWN NOSAVE | timeout 1s $REDIS_CLI -h $TARGET_IP --pipe &>/dev/null
}

launch_process() {
	local kv_num="$1"
	local results_file="$RESULTS_PROCESS_DIR/snapshot-$kv_num"

	DB_FILE="/root/9p-mnt/dump.rdb"

	# cleanup
	killall redis-server &>/dev/null
	rm $DB_FILE &>/dev/null
	#sleep 2

	echo "Launch process.."

	# start redis
	$REDIS_SRV $ROOTFS/redis.process.conf 2>> $results_file &
	#$REDIS_SRV /root/images/unikraft/experiments/redis/redis.conf 2> $results_file &
	sleep 3

	TARGET_IP="10.8.0.1"
	if [ $HOSTNAME = "computer2" ]; then 
		CPU=14
	elif [ $HOSTNAME = "computer10" ]; then 
		CPU=1
	elif [ $HOSTNAME = "c428" ]; then 
		CPU=1
	elif [ $HOSTNAME = "c429" ]; then 
		CPU=1
	elif [ $HOSTNAME = "alpine-vm" ]; then 
		CPU=1
		TARGET_IP="10.0.0.2"
	fi

	while read pid; do
		taskset --cpu-list -p $CPU $pid
		CPU=$((CPU + 1))
	done < <(pgrep redis)

	do_single_snapshot

	# populate the database
	if [ $kv_num -gt 0 ]; then
		cat $DATA_FILE | $REDIS_CLI -h $TARGET_IP --pipe &>/dev/null
	fi

	if [ $kv_num -eq 1000000 ]; then
		SLEEP_SEC=10
	else
		SLEEP_SEC=2
	fi
}

generate_config_file() {
	export APP_MEMORY="$vm_mem"
	export APP_PERC="$vm_perc"

	envsubst < $XL_CFG_TMPL > $XL_CFG_GENERATED
}

launch_vm() {
	echo "Launch vm.."

	DB_FILE="$ROOTFS/root/dump.rdb"

	# cleanup
	/root/scripts/xen/destroy-domains.sh &>/dev/null
	rm $DB_FILE &>/dev/null

	# start redis
	xl create $XL_CFG_GENERATED

	TARGET_IP="10.8.0.2"

	# wait VM to be up
	local connected=0
	while [ $connected -eq 0 ]; do
		ping -c 1 -W 3 $TARGET_IP &>/dev/null && connected=1
	done
	sleep 1

	do_single_snapshot

	/root/scripts/xen/pin-qemu.sh

	# populate the database
	if [ $kv_num -gt 0 ]; then
		echo -ne "Populating database.."
		$SCRIPT_DIR/send-batched-data.sh $DATA_FILE
		echo "Done"
	fi

	if [ $kv_num -eq 1000000 ]; then
		SLEEP_SEC=10
	else
		SLEEP_SEC=2
	fi
}

run_experiment() {
	local kv_num="$1"
	local vm_mem="$2"
	local vm_perc="$3"

	if [ $SKIP_PROCESS -eq 0 ]; then
		VM_ROUND=0

		# recreate results dir
		local results_dir="$RESULTS_PROCESS_DIR/$kv_num"
		recreate_dir $results_dir

		# generate the data file which will be used to populate the database
		[ $kv_num -gt 0 ] && generate_mass_data $kv_num 

		for i in $(seq $REPETITIONS); do
			echo "repetition $i"
			launch_process $kv_num
			do_snapshots
		done

		collect_results_process $kv_num
	fi

	if [ $SKIP_VM -eq 0 ]; then
		VM_ROUND=1
		# find memory params
		if [ -z $vm_mem ]; then
			$SCRIPT_DIR/mem-searcher.sh
			exit
		fi

		if [ ! -f $XENCLONED_LOG ]; then
			echo "$XENCLONED_LOG does not exist!"
			exit -2
		fi

		# recreate results dir
		local results_dir="$RESULTS_VM_DIR/$kv_num"
		recreate_dir $results_dir

		BREAKDOWN_RESULTS="$results_dir/breakdown"
		truncate -s 0 $BREAKDOWN_RESULTS

		# generate the data file which will be used to populate the database
		#[ $kv_num -gt 0 ] && generate_mass_data $kv_num 

		# generate ramfs
		#TODO /root/images/unikraft/scripts/create-ramfs.sh $ROOTFS $EXPERIMENT_ROOT_DIR/initramfs.cpio

		generate_config_file

		for i in $(seq $REPETITIONS); do
			echo "repetition $i"
			launch_vm
			do_snapshots
			collect_results_vm $kv_num
		done
	fi
}

KV_NUM=(\
	"0;18;70"
	"1;18;70"
	"10;26;70"
	"100;27;90"
	"1000;27;90"
	"10000;28;80"
	"100000;42;90"
	"1000000;256;90"
)

for i in ${KV_NUM[@]}; do
	IFS=';' read kv_num vm_mem vm_perc < <(echo $i)
	echo "kv_num=$kv_num"
	run_experiment $kv_num $vm_mem $vm_perc
	sleep 5
done

