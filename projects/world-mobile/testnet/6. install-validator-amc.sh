#!/usr/bin/env bash
echo "Setting Variables"
# Define target network chain ID
CHAIN_ID="aya_preview_501"
AYA_P2P_PORT=26656
AYA_RPC_PORT=26657

# Set the path to the aya home directory
aya_home=/opt/aya
# Set the path to the current script
validator_json=${aya_home}/validator.json
# Set the path to the json file with validator registration
en_registration_json=${aya_home}/registration.json
# Set the path to the file with the account name

# Prompt user for configuration variables
echo "Prompting user for configuration variables..."
# Prompt for MONIKER with a default value
read -p "Enter MONIKER (default: Skint-Earth-Node-1): " MONIKER
MONIKER=${MONIKER:-Skint-Earth-Node-1}
# Prompt for ACCOUNT with a default value
read -p "Enter ACCOUNT (default: Skint-Earth-Node-1): " ACCOUNT
ACCOUNT=${ACCOUNT:-Skint-Earth-Node-1}
# Prompt for SENTRY1_NODE_IP with a default value
read -p "Enter SENTRY1_NODE_IP (default: 192.168.8.101): " SENTRY1_NODE_IP
SENTRY1_NODE_IP=${SENTRY1_NODE_IP:-192.168.8.101}
echo "Configured MONIKER: $MONIKER"
echo "Configured ACCOUNT: $ACCOUNT"
echo "Configured SENTRY1 NODE IP: $SENTRY1_NODE_IP"

echo "Installing Aya Missions Control"
cd ${HOME}
git clone https://github.com/Sbcdn/aya-mission-control.git
cd aya-mission-control/
sudo chmod +x ./install_script.sh
./install_script.sh
sudo systemctl status aya_mission_control.service
# Obtaining the operator_address
cd ${aya_home}
operator_address=$(jq -r '.operator_address' registration.json)
echo $operator_address
# Obtaining the account_hex_address
output1=$(ayad keys parse ${operator_address})
# Extract the address
account_hex_address=$(echo "$output1" | grep bytes | awk '{print $2}')
echo $account_hex_address
# Run the command and extract the third address
consensus_address=$(ayad keys parse ${account_hex_address} | awk '/^-/ {count++; if (count == 3) print $2}')
# Use the consensus address
echo $consensus_address

echo "Creating a function to modify AYA Config Files ..."
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

# Declaring another associative array for the app.toml changes
declare -A sections3
sections3["global,val_operator_addr,1"]="${consensus_address}"
sections3["global,account_addr,1"]="${ACCOUNT}"
sections3["global,validator_hex_addr,1"]="${account_hex_address}"
sections3["global,external_rpc,1"]="http://${SENTRY1_NODE_IP}:${AYA_RPC_PORT}"
sections3["global,validator_name,1"]="${MONIKER}"
# sections3["global,enable_telegram_alerts,1"]="no"
# sections3["global,enable_email_alerts,1"]="no"
# Iterate over each composite key for the app.toml changes and apply the updates
for compositeKey in "${!sections2[@]}"; do
    IFS=',' read -r section key quote <<< "$compositeKey"
    value="${sections3[$compositeKey]}"
    update_config "${aya_home}"/amc/config.toml "$section" "$key" "$value" "$quote"
done

sudo systemctl restart aya_mission_control.service
sudo systemctl status aya_mission_control.service
