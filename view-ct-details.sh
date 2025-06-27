#!/bin/bash

if [[ -z "$1" ]]; then
  echo "Usage: $0 <CTID>"
  exit 1
fi

vmid="$1"

if ! pct status "$vmid" &>/dev/null; then
  echo "Container $vmid not found."
  exit 1
fi

hostname=$(pct exec "$vmid" -- hostname 2>/dev/null || echo "unavailable")

# RAM
mem_info=$(pct exec "$vmid" -- awk '/MemTotal|MemFree/ {gsub(/kB/, "", $2); print $2}' /proc/meminfo 2>/dev/null | paste -sd " ")
if [[ -n "$mem_info" ]]; then
  mem_total_kb=$(echo "$mem_info" | awk '{print $1}')
  mem_free_kb=$(echo "$mem_info" | awk '{print $2}')
  mem_used_kb=$((mem_total_kb - mem_free_kb))
  mem_str="$((mem_used_kb / 1024))MB / $((mem_total_kb / 1024))MB"
else
  mem_str="N/A"
fi

# Disk
disk=$(pct exec "$vmid" -- df -h / 2>/dev/null | awk 'NR==2 {print $3 "/" $2}' || echo "N/A")

# CPU
cpu=$(pct exec "$vmid" -- top -b -n1 2>/dev/null | awk '/^%Cpu/ {print $2 + $4}' || echo "N/A")
[[ "$cpu" != "N/A" ]] && cpu="${cpu}%"

# IP
ips=$(pct exec "$vmid" -- hostname -I 2>/dev/null | tr -d '\n' || echo "N/A")

echo "Container $vmid"
echo "Hostname  : $hostname"
echo "RAM       : $mem_str"
echo "Disk      : $disk"
echo "CPU       : $cpu"
echo "IP(s)     : $ips"
