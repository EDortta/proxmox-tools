#!/bin/bash
set -e

LOG_FILE="authfy-infrastructure.log"
echo "You can do tail -f $LOG_FILE to watch the progress"

# Function to log messages to a file
log_info() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >> "$LOG_FILE"
}

# Get the DNSMasq container's IP
dnsmasq_vmid=$(pct list | awk -v hostname="dnsmasq-ct" '$3 == hostname {print $1}')
if [ -n "$dnsmasq_vmid" ]; then
  dnsmasq_ip=$(pct exec "$dnsmasq_vmid" -- ip -4 addr show eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
else
  dnsmasq_ip="8.8.8.8"
fi

get_best_bridge() {
    jq -r '.bridge // "vmbr0"' config.json
}

get_best_nat() {
    jq -r '.nat // .NAT // "vmbr2"' config.json
}

create_ct() {
    container_name=$1
    template=$2
    bridged=$3
    root_password=$4
    storage="local-lvm"

    existing_vmid=$(pct list | awk -v name="$container_name" '$3 == name {print $1}')
    if [[ -n "$existing_vmid" ]]; then
        log_info "Error: Container '$container_name' already exists (VMID: $existing_vmid)."
        return 1
    fi

    log_info "======================================================================"
    log_info "Creating $container_name"
    
    last_vmid=$(pct list | awk '$1 ~ /^[0-9]+$/ {print $1}' | sort -n | tail -n 1)
    vmid=$(( ${last_vmid:-199} + 1 ))
    
    bridge_eth0=$(get_best_bridge)
    nat_eth1=$(get_best_nat)
    
    log_info "Selected NAT interface for eth1: $nat_eth1"

    log_info "Creating new container with VMID: $vmid"
    if ! pct create "$vmid" "$template" --storage "$storage" --hostname "$container_name" >/dev/null 2>&1; then
        log_info "Error: Failed to create container $container_name"
        return 1
    fi
    
    pct start "$vmid"
    log_info "Container started"

    if [[ "$bridged" -gt 0 ]]; then
        log_info "Configuring eth0 (bridged) on $bridge_eth0"
        pct set "$vmid" --net0 name=eth0,bridge="$bridge_eth0",ip=dhcp
    else
        log_info "Skipping eth0 setup (bridged=$bridged)"
    fi

    log_info "Configuring eth1 (NAT) on $nat_eth1"
    pct set "$vmid" --net1 name=eth1,bridge="$nat_eth1",ip=dhcp,firewall=1

    log_info "Configuring DNS settings"
    pct exec "$vmid" -- /bin/sh -c "chattr -i /etc/resolv.conf; echo 'nameserver $dnsmasq_ip' > /etc/resolv.conf; echo 'nameserver 208.67.222.222' >> /etc/resolv.conf"

    if [[ "$template" == *"alpine"* ]]; then
        log_info "Configuring Alpine networking"

        # Fix Alpine repositories (mirror fallback)
        pct exec "$vmid" -- /bin/sh -c "sed -i 's|dl-cdn.alpinelinux.org|mirror.math.princeton.edu/pub/alpinelinux|g' /etc/apk/repositories"

        # Ensure package manager works correctly
        pct exec "$vmid" -- /bin/sh -c "apk update && apk add --no-cache e2fsprogs" 2>/dev/null
        
    elif [[ "$template" == *"debian"* ]]; then
        log_info "Configuring Debian networking"
        pct exec "$vmid" -- /bin/sh -c "apt-get update -y && apt-get install -y resolvconf e2fsprogs"
    fi

    log_info "Configuring networking"

    # Ensure loopback is always set
    pct exec "$vmid" -- /bin/sh -c "echo -e 'auto lo\niface lo inet loopback' > /etc/network/interfaces"

    if [[ "$bridged" -gt 0 ]]; then
        log_info "Configuring eth0 (bridged) on $bridge_eth0"
        pct set "$vmid" --net0 name=eth0,bridge="$bridge_eth0",ip=dhcp
        pct exec "$vmid" -- /bin/sh -c "echo -e 'auto eth0\niface eth0 inet dhcp\ndns-nameservers $dnsmasq_ip 208.67.222.222' >> /etc/network/interfaces"
    fi

    log_info "Configuring eth1 (NAT) on $nat_eth1"
    pct set "$vmid" --net1 name=eth1,bridge="$nat_eth1",ip=dhcp,firewall=1
    pct exec "$vmid" -- /bin/sh -c "echo -e 'auto eth1\niface eth1 inet dhcp' >> /etc/network/interfaces"

    # Restart networking to get IP via DHCP
    log_info "Restarting networking to obtain DHCP lease for eth1"
    $(pct exec "$vmid" -- /bin/sh -c "/etc/init.d/networking restart || reboot") 2> /dev/null

    # Wait for eth1 to get an IP
    log_info "Waiting for eth1 to get an IP..."
    while true; do
        eth1_ip=$(pct exec "$vmid" -- /bin/sh -c "ip -4 addr show eth1 | awk '/inet / {print \$2}' | cut -d'/' -f1" | tr -d '\r')
        if [[ -n "$eth1_ip" ]]; then
            log_info "eth1 assigned IP: $eth1_ip"
            break
        fi
        sleep 2
    done

    # Convert eth1 to static with the same IP
    log_info "Converting eth1 to static IP: $eth1_ip"

    if [[ "$template" == *"alpine"* ]]; then
        pct exec "$vmid" -- /bin/sh -c "echo -e 'auto eth1\niface eth1 inet static\naddress $eth1_ip\nnetmask 255.255.255.0\ndns-nameservers $dnsmasq_ip 208.67.222.222' > /etc/network/interfaces"
    elif [[ "$template" == *"debian"* ]]; then
        pct exec "$vmid" -- /bin/sh -c "echo -e 'auto eth1\niface eth1 inet static\naddress $eth1_ip\nnetmask 255.255.255.0\ndns-nameservers $dnsmasq_ip 208.67.222.222' > /etc/network/interfaces"
    fi

    # Restart networking to apply static IP
    log_info "Applying static IP for eth1"
    pct exec "$vmid" -- /bin/sh -c "/etc/init.d/networking restart || reboot"

    log_info "Restarting container"
    pct stop "$vmid"
    sleep 2
    pct start "$vmid"
    
    while true; do
        sleep 5
        status=$(pct status "$vmid" | awk '{print $2}')
        if [[ "$status" == "running" ]]; then
            log_info "Container $vmid is running again."
            break
        fi
    done

    log_info "Setting root password"
    pct exec "$vmid" -- /bin/sh -c "echo 'root:$root_password' | chpasswd"

    # **Fix VMID output issue** (remove extra text)
    printf "%d\n" "$vmid"
}
