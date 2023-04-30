#!/bin/bash
set -e

SCRIPT_DIR="$(dirname $0)"
EXPERIMENT_DIR="$(realpath $SCRIPT_DIR/..)"

# cleanup
/root/scripts/xen/destroy-domains.sh

# (1) launch nginx
XL_CFG="$EXPERIMENT_DIR/config-nginx-$(hostname)"
xl create $XL_CFG


# (2) wait for all workers
ROOTFS="$EXPERIMENT_DIR/rootfs"
CONFIG_FILE="$ROOTFS/nginx/conf/worker_process.conf"

worker_processes=$(cat $CONFIG_FILE | grep worker_processes | sed 's/worker_processes \([0-9]\+\);/\1/')

wait_children_boot() {
	local name_prefix="$1"
	local expected="$2"
	local found=0 
	set +e
	while [ $found -lt $expected ]; do
		sleep 1
		found=$(xl list | grep "$name_prefix"-child | wc -l)
	done
	set -e
}
wait_children_boot "unikraft-nginx" $worker_processes

# (3) custom IO operations
bridge_type="bond"
if [ "$bridge_type" = "ovs" ]; then
	# (3.1) remove parent netif from OVS bucket
	group_id=$(ovs-ofctl dump-groups ovs-br0 | grep -o 'group_id=[0-9]\+' | cut -d'=' -f2)
	ovs-ofctl remove-buckets ovs-br0 group_id=$group_id,command_bucket_id=0
elif [ "$bridge_type" = "bond" ]; then
	# (3.2) wake up guest for ARP table update
	$SCRIPT_DIR/arping-vifs.sh 1
	
	# (3.2) remove parent netif from bond
	first_vif=$(ip l show | grep -o 'vif[0-9]\+.[0-9]\+' | head -n 1)
	ip link set $first_vif nomaster
fi

#name=$(grep name $XL_CFG | cut -d'"' -f2)
#parent_id=$(xl list | grep $name | head -n 1 | tr -s ' ' | cut -d' ' -f2)
#xl pause $parent_id

# (4) pin vifs
$SCRIPT_DIR/pin-cloned-vifs.sh

