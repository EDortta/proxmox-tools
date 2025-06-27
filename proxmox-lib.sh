#!/bin/bash
# proxmox-lib.sh

if ! [ -x "$(command -v jq)" ]; then
    echo 'jq is not installed. Please install it before running this script.' >&2
    exit 1
fi

if [ ! -f "$(dirname "${BASH_SOURCE[0]}")/config.json" ]; then
  cat > "$(dirname "${BASH_SOURCE[0]}")/config.json" <<EOF
{
  "ctid": {
    "containers": 200,
    "templates": 100
  }
}
EOF
fi

function get_initial_ctid() {
  local config_file="config.json"
  local containers=$(jq -r ".ctid.containers" "$config_file")
  echo "$containers"
}

function get_initial_tid() {
  local config_file="config.json"
  local templates=$(jq -r ".ctid.templates" "$config_file")
  echo "$templates"
}

list_templates() {
    echo "Available LXC Templates:"
    ls /var/lib/vz/template/cache/ | grep -E '\.tar\.(gz|zst)$'
}

