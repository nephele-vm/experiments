#!/bin/bash

while read vif; do
	[ ! -z "$1" ] && echo "arpinging $vif.."
	arping -c 1 -I $vif 10.8.0.2 -s 10.8.0.1 &>/dev/null
done < <(ip link show | grep vif | sed 's/^.*\(vif[0-9]\+.[0-9]\+\).*$/\1/g')

