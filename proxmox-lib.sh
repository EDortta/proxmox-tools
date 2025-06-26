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
    "initial_value": 100
  }
}
EOF
fi

function get_initial_ctid() {
  local config_file="config.json"
  local initial_value=$(jq -r ".ctid.initial_value" "$config_file")
  echo "$initial_value"
}
