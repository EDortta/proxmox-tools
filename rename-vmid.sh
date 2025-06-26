#!/bin/bash

if [ -z "$2" ]; then
    echo "Usage: $0 <VMID> <hostname>"
    exit 1
fi



pct exec $1 -- bash -c "echo $2 > /etc/hostname && hostname $2"

