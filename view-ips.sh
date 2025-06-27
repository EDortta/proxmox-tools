#!/bin/bash
set -e

source ./proxmox-lib.sh

VMID=$(get_initial_ctid)

echo "Listing IPs for containers with VM IDs >= $VMID"
echo "------------------------------------------------------------------------------------"
printf "%-6s %-35s %-16s %-16s\n" "VMID" "Hostname" "Ext.IP" "Int.IP"
echo "------------------------------------------------------------------------------------"

while read -r vmid; do
    hostname=$(pct exec "$vmid" -- hostname 2>/dev/null || echo "???")
    ip0=$(pct exec "$vmid" -- ip -4 addr show dev eth0 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    ip1=$(pct exec "$vmid" -- ip -4 addr show dev eth1 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)

    printf "%-6s %-35s %-16s %-16s\n" "$vmid" "$hostname" "${ip0:-unattached}" "${ip1:-unattached}"
done < <(pct list | awk -v vmid="$VMID" '$1 >= vmid && $2 == "running" {print $1}')

echo "------------------------------------------------------------------------------------"
