#!/bin/bash

REDIS_CLI="/root/images/unikraft/experiments/redis/process/redis-cli"

echo BGSAVE | $REDIS_CLI -h 10.8.0.2 --pipe
sleep 2

last_vif=$(ip l show | grep -o 'vif[0-9]\+.[0-9]\+' | tail -n 1)
ip link set $last_vif nomaster

