#!/bin/bash

SCRIPT_DIR="$(dirname $0)"

EXPERIMENT_ROOT_DIR="$(realpath $SCRIPT_DIR/..)"

XL_CFG_TMPL="$EXPERIMENT_ROOT_DIR/config-redis-mem-searcher.tmpl"
XL_CFG_GENERATED="$EXPERIMENT_ROOT_DIR/config-redis-mem-searcher.generated"

VM_NAME=$(grep '^name' $XL_CFG_TMPL | cut -d'"' -f2)
LOGFILE="/var/log/xen/guest/guest-$VM_NAME.log"

generate_config_file() {
	local memory="$1"

	export APP_MEMORY="$memory"

	envsubst < $XL_CFG_TMPL > $XL_CFG_GENERATED
}

check_vm_crashed() {
	local vm_status=$(xl list | grep $VM_NAME | tr -s ' ' | cut -d' ' -f5)
	echo $vm_status | grep 'c' &>/dev/null
	return $?
}

launch_vm() {
	# cleanup
	/root/scripts/xen/destroy-domains.sh
	rm $LOGFILE

	# start redis
	xl create $XL_CFG_GENERATED &>/dev/null

	TARGET_IP="10.8.0.2"

	# wait VM to be up
	local connected=0
	while [ $connected -eq 0 ]; do
		if ping -c 1 -W 3 $TARGET_IP &>/dev/null; then
			connected=1
			sleep 5
			check_vm_crashed && return 1

			grep "Not enough contiguous pages available" $LOGFILE &>/dev/null && return 1
			grep "Not enough pages available" $LOGFILE &>/dev/null && return 1
		else
			check_vm_crashed && return 1
		fi
	done
	return 0
}

try_size() {
	generate_config_file $1
	launch_vm
	return $?
}

START_VAL=10
END_VAL=$(($START_VAL * 2))
END_OK=0
while [ $START_VAL -lt $(( $END_VAL - 1 )) ]; do
	MEAN=$(( ($START_VAL + $END_VAL) / 2))
	#echo "Trying $MEAN"
	try_size $MEAN
	if [ $? -eq 0 ]; then
		#echo "Found a candidate: $MEAN"
		END_OK=$MEAN
		END_VAL=$END_OK
	else
		START_VAL=$MEAN
		[ $END_OK -gt 0 ] && END_VAL=$END_OK || END_VAL=$(($START_VAL * 2))
	fi
done
echo "$END_VAL"

