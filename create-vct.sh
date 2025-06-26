#!/bin/bash

source ./proxmox-lib.sh

# Default values
DEFAULT_RAM="2048"
DEFAULT_DISK="8" 
DEFAULT_CORES=2
DEFAULT_STORAGE="local-lvm"
DEFAULT_BRIDGE="vmbr0"
DEFAULT_ROOT_PASS="ags2025"
DEFAULT_USER="desenvolvedor"
DEFAULT_USER_PASS="DevelP4ssword"
NODE_NAME=$(hostname)      

# Function to list available LXC templates
list_templates() {
    echo "Available LXC Templates:"
    ls /var/lib/vz/template/cache/ | grep -E '\.tar\.(gz|zst)$'
}

setup_users() {
    local vmid="$1"
    local root_password="$2"
    local username="$3"
    local user_password="$4"
    local enable_sudo="${5:-true}"  # Optional, default: true

    echo "Setting root password..."
    pct exec "$vmid" -- /bin/sh -c "echo 'root:$root_password' | chpasswd"

    echo "Detecting container OS..."
    os_type=$(pct exec "$vmid" -- cat /etc/os-release | grep ^ID= | cut -d= -f2 | tr -d '"')

    if [[ "$os_type" == "alpine" ]]; then
        echo "Detected Alpine Linux"
        echo "Creating user: $username"
        pct exec "$vmid" -- adduser -D -s /bin/sh "$username"
        pct exec "$vmid" -- /bin/sh -c "echo '$username:$user_password' | chpasswd"
        if [[ "$enable_sudo" == true ]]; then
            echo "Installing sudo and adding user to wheel group..."
            pct exec "$vmid" -- apk add sudo
            pct exec "$vmid" -- addgroup "$username" wheel
            pct exec "$vmid" -- sh -c "echo '%wheel ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/wheel"
        fi
    else
        echo "Detected Debian/Ubuntu"
        echo "Creating user: $username"
        pct exec "$vmid" -- useradd -m -s /bin/bash "$username"
        pct exec "$vmid" -- /bin/bash -c "echo '$username:$user_password' | chpasswd"
        if [[ "$enable_sudo" == true ]]; then
            echo "Installing sudo and granting user sudo access..."
            pct exec "$vmid" -- apt-get update -y >/dev/null
            pct exec "$vmid" -- apt-get install -y sudo >/dev/null
            pct exec "$vmid" -- usermod -aG sudo "$username"
            pct exec "$vmid" -- bash -c "echo '$username ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/$username"
        fi
    fi

    echo "User setup complete."
}


# Function to create an LXC container
create_lxc() {
    local template=$1
    local ram=$2
    local disk=$3
    local cores=$4

    local base_vmid=$(get_initial_ctid)

    local vmid
    vmid=$(pvesh get /cluster/nextid)

    if (( $vmid < $base_vmid )); then
        vmid=$base_vmid
    fi

    echo "Creating LXC container..."
    echo "  Template: $template"
    echo "  VMID: $vmid"
    echo "  RAM: $ram MB"
    echo "  Disk: $disk"
    echo "  Cores: $cores"
    echo "  Storage: $DEFAULT_STORAGE"

    # Use an array for the command
    cmd="pct create "$vmid" "local:vztmpl/$template" --hostname "lxc-$vmid" --memory "$ram" --cores "$cores" --rootfs "$DEFAULT_STORAGE:$disk" --net0 "name=eth0,bridge=$DEFAULT_BRIDGE,ip=dhcp,ip6=auto,firewall=1" --start 1"

    echo "Command to be executed:"
    echo "  $cmd"
    echo

    if $cmd; then
        echo "LXC $vmid created and started successfully!"
        
        sleep 3

        setup_users "$vmid" "$DEFAULT_ROOT_PASS" "$DEFAULT_USER" "$DEFAULT_USER_PASS"

        echo "Container $vmid setup complete!"

        ip=$(pct exec "$vmid" -- hostname -I | awk '{print $1}')
        pct set "$vmid" --net0 name=eth0,bridge=$DEFAULT_BRIDGE,ip=${ip}/24,gw=192.168.2.2,ip6=auto,firewall=1
        pct set "$vmid" --net1 name=eth1,bridge=vmbr1,ip=172.18.32.$((vmid - 100))/24,firewall=1
        echo "Container IP: $ip"        
    else
        echo "Failed to create LXC $vmid. Check logs above."
    fi

}

# If no parameters, show usage and list templates
if [ "$#" -eq 0 ]; then
    echo "Usage: $0 --template <template-name> [--ram <MB>] [--disk <size>] [--cores <number>]"
    list_templates
    exit 1
fi

# Argument parsing
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --template) template="$2"; shift ;;
        --ram) ram="$2"; shift ;;
        --disk) disk="$2"; shift ;;
        --cores) cores="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# Use defaults if not provided
ram=${ram:-$DEFAULT_RAM}
disk=${disk:-$DEFAULT_DISK}
cores=${cores:-$DEFAULT_CORES}

# Template required
if [ -z "$template" ]; then
    echo "No template specified."
    list_templates
    exit 1
fi

# Run creation
create_lxc "$template" "$ram" "$disk" "$cores"
