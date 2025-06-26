#!/bin/bash
# view-disk-usage
set -e

echo "Listing virtual disk sizes for containers with VM IDs >= 100"
echo "----------------------------------------------------------"
echo -e "VMID\tHostname\t\tDisk\t\tUsed"
echo "----------------------------------------------------------"

pct list  | grep -vw VMID | awk '$1 >= 100 {print $1, $3}' | while read -r vmid hostname; do
    # Find root volume path
    disk=$(pct config "$vmid" | grep "^rootfs:" | cut -d, -f1 | awk '{print $2}')
    
    if [[ "$disk" == local-* ]]; then
        lv=$(echo "$disk" | cut -d: -f2)
        size=$(lvs --noheadings -o LV_SIZE "/dev/pve/${lv}" 2>/dev/null | tr -d ' ')
        used=$(lvs --noheadings -o data_percent "/dev/pve/${lv}" 2>/dev/null | tr -d ' ')
        used="${used:-N/A}%"
        printf "%-5s\t%-20s\t%-8s\t%s\n" "$vmid" "$hostname" "$size" "$used"
    else
        printf "%-5s\t%-20s\t%-8s\t%s\n" "$vmid" "$hostname" "N/A" "N/A"
    fi
done

echo "----------------------------------------------------------"
