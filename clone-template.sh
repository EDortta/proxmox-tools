#!/bin/bash
set -e
source ./proxmox-lib.sh

DEFAULT_DISK="80"
TEMPLATE_ID=112

if [ -z "$1" ]; then
    echo "Indique o nome da máquina que deseja criar"
    echo "Uso: $0 <nome> [--disk <tamanho-em-GB>] [--template <template-id>]"
    exit 100
fi

HOST_PREFIX="$1"
shift

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --disk)
            DISK_SIZE="$2"
            shift
            ;;
        --template)
            TEMPLATE_ID="$2"
            shift
            ;;
        *)
            echo "Parâmetro desconhecido: $1"
            exit 1
            ;;
    esac
    shift
done

DISK_SIZE="${DISK_SIZE:-$DEFAULT_DISK}"

VMID=$(pvesh get /cluster/nextid)
base_vmid=$(get_initial_ctid)

if (( $VMID < $base_vmid )); then
    VMID=$base_vmid
fi

HOSTNAME="${HOST_PREFIX}-${VMID}"

echo "Clonando container $TEMPLATE_ID para $VMID (hostname: $HOSTNAME)..."

if pct clone "$TEMPLATE_ID" "$VMID" --hostname "$HOSTNAME" 2>/tmp/clone_error.log; then
    echo "Linked clone feito com sucesso."
else
    echo "Linked clone falhou. Tentando clone completo..."

    TEMPLATE_ROOTFS=$(pct config "$TEMPLATE_ID" | grep '^rootfs:' | awk '{print $2}')
    STORAGE=$(echo "$TEMPLATE_ROOTFS" | cut -d: -f1)

    pct clone "$TEMPLATE_ID" "$VMID" --full 1 --storage "$STORAGE" --hostname "$HOSTNAME"
    echo "Clone completo feito com sucesso."
fi

echo -n "Aguardando o processo de clonagem finalizar... "
spin='-\|/'
i=0
while [ ! -f "/etc/pve/lxc/$VMID.conf" ]; do
    i=$(( (i + 1 ) % 4 ))
    printf "\b${spin:$i:1}"
    sleep 0.2
done
printf "\b"
echo " Pronto!"

echo "Redimensionando disco para ${DISK_SIZE}G..."
pct resize "$VMID" rootfs "${DISK_SIZE}G"

echo "Iniciando o container novo..."
pct start "$VMID"

echo "Configurando IPs do container..."
config=$(cat "$(dirname "${BASH_SOURCE[0]}")/config.json")

bridge=$(jq -r '.network.bridge.bridge' <<< "$config")
gateway=$(jq -r '.network.bridge.gateway' <<< "$config")
mask=$(jq -r '.network.bridge.mask' <<< "$config")
net=$(jq -r '.network.bridge.net' <<< "$config")
eth=$(jq -r '.network.bridge.name' <<< "$config")

nat_bridge=$(jq -r '.network.nat.bridge' <<< "$config")
nat_base=$(jq -r '.network.nat.base' <<< "$config")
nat_mask=$(jq -r '.network.nat.mask' <<< "$config")
nat_net=$(jq -r '.network.nat.net' <<< "$config")
nat_eth=$(jq -r '.network.nat.name' <<< "$config")

ip=$(pct exec "$VMID" -- hostname -I | awk '{print $1}')
pct set "$VMID" --$net name=$eth,bridge="$bridge",ip=${ip}/$mask,gw=$gateway,ip6=auto,firewall=1
pct set "$VMID" --$nat_net name=$nat_eth,bridge="$nat_bridge",ip=${nat_base}.$((VMID - $base_vmid))/$nat_mask,firewall=1

