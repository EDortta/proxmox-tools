#!/bin/bash
set -e

source ./proxmox-lib.sh

VMID=$(get_initial_ctid)

echo "Listing IPs for containers with VM IDs >= $VMID"
echo "----------------------------------------------------------"
echo -e "VMID\tHostname\t\tExt.IP\t\tInt.IP"
echo "----------------------------------------------------------"

pct list | grep -w running | awk '$1 >= $VMID {print $1}' | while read -r vmid; do
    hostname=$(pct exec "$vmid" -- hostname)

    ip0=$(pct exec "$vmid" -- ip -4 addr show dev eth0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)

    ip1=$(pct exec "$vmid" -- ip -4 addr show dev eth1 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)

    printf "%-5s\t%-20s\t%s %s\n" "$vmid" "$hostname" "${ip0:-unattached}" "${ip1:-unattached}"
done
echo "----------------------------------------------------------"

