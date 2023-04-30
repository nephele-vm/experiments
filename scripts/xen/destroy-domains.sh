#!/bin/bash

#toolstack="$1"
toolstack="xl"
num=$(xl list | wc -l)
while [ $num -gt 2 ]; do
        for i in $(xl list | tail -n +3 | head -n 100 | tr -s ' ' | cut -d' ' -f2); do $toolstack destroy $i; done
        num=$(xl list | wc -l)
done

