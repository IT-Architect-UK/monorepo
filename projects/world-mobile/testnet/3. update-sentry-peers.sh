#!/usr/bin/env bash

# Begin logging again inside the sudo block
LOG_FILE="/home/wmt/scripts/update-sentry.log"
exec > >(tee -a $LOG_FILE)
exec 2> >(tee -a $LOG_FILE >&2)

# Dependency Check Function
check_dependency() {
    for cmd in "$@"; do
        if ! command -v $cmd &> /dev/null; then
            echo "$cmd is not installed. Installing now..."
            sudo apt-get -q install $cmd -y
        fi
    done
}

# Setting Variables
aya_home="/opt/aya"
config_file="/opt/aya/config/config.toml"

echo "Modifying the $aya_home/config/config.toml parameters"
validator_node_id="bb2f62e7e9ab965d05b9da50a66260d0d8062e8d"
validator_ip="192.168.8.100"
validator_port="26656"
persistent_peers="692f6bb765ed3170db4fb5f5dfd27c54503d52d3@peer1-501.worldmobilelabs.com:26656,d1da4b1ad17ea35cf8c1713959b430a95743afcd@peer2-501.worldmobilelabs.com:26656,$validator_node_id@$validator_ip:$validator_port"
laddr="tcp://0.0.0.0:26657" # TCP or UNIX socket address for the RPC server to listen on

# Function to update values in a specific section of a config file
update_config() {
    local file="$1"
    local section="$2"
    local key="$3"
    local value="$4"
    local quote="$5"

    if [[ "$quote" == "1" ]]; then
        value="\"$value\""
    fi

    sudo awk -v section="$section" -v key="$key" -v value="$value" '
    BEGIN {
        if (section == "global") {
            in_section = 1
        } else {
            in_section = 0
        }
    }
    in_section {
        if ($1 == key && $2 == "=") {
            print key " = " value
            next
        }
    }
    $0 == "[" section "]" {
        in_section = 1
    }
    $0 ~ /^\[.*\]$/ && $0 != "[" section "]" {
        in_section = 0
    }
    {
        print
    }' "$file" > "${file}.tmp"
    sudo mv "${file}.tmp" "$file"
}

echo "Modifying the config.toml parameters post initial sync"
# Declaring an associative array with composite keys
declare -A sections
sections["p2p,persistent_peers,1"]="$persistent_peers"
sections["p2p,unconditional_peer_ids,1"]="$validator_node_id"
sections["p2p,private_peer_ids,1"]="$validator_node_id"
sections["p2p,laddr,1"]="tcp://0.0.0.0:26656"
sections["rpc,laddr,1"]="tcp://0.0.0.0:26657"
# Iterate over each composite key and apply the changes
for compositeKey in "${!sections[@]}"; do
    IFS=',' read -r section key quote <<< "$compositeKey"
    value="${sections[$compositeKey]}"
    update_config "$config_file" "$section" "$key" "$value" "$quote"
done

echo "Modifying the app.toml parameters"
config_file2="/opt/aya/config/app.toml"
# Create a backup of the original file with .bkp suffix
cp -f "$config_file2" "${config_file2}.bkp"
echo "Backup created as ${config_file2}.bkp"
# Declaring another associative array for the app.toml changes
declare -A sections2
sections2["grpc-web,snapshot-interval,0"]="100"
# Iterate over each composite key for the app.toml changes and apply the updates
for compositeKey in "${!sections2[@]}"; do
    IFS=',' read -r section key quote <<< "$compositeKey"
    value="${sections2[$compositeKey]}"
    update_config "$config_file2" "$section" "$key" "$value" "$quote"
done

# Restart the Sentry node services
sudo systemctl restart cosmovisor.service
sudo systemctl status cosmovisor.service
