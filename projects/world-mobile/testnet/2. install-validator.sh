#!/usr/bin/env bash
echo "Setting Variables"
# Define target network chain ID
CHAIN_ID="aya_preview_501"
AYA_P2P_PORT=26656
AYA_RPC_PORT=26657
AYA_SEED_NODE="peer3-501.worldmobilelabs.com"
AYA_SEED_URL="http://$AYA_SEED_NODE"

# Prompt user for configuration variables
echo "Prompting user for configuration variables..."
# Prompt for MONIKER with a default value
read -p "Enter MONIKER (default: Skint-Earth-Node-1): " MONIKER
MONIKER=${MONIKER:-Skint-Earth-Node-1}
# Prompt for ACCOUNT with a default value
read -p "Enter ACCOUNT (default: Skint-Earth-Node-1): " ACCOUNT
ACCOUNT=${ACCOUNT:-Skint-Earth-Node-1}
# Prompt for SENTRY1_NODE_ID with a default value
read -p "Enter SENTRY1_NODE_ID (default: 7b6ffac8e44c95aaf4e70f35cca07857eced8b84): " SENTRY1_NODE_ID
SENTRY1_NODE_ID=${SENTRY1_NODE_ID:-7b6ffac8e44c95aaf4e70f35cca07857eced8b84}
# Prompt for SENTRY2_NODE_ID with a default value
read -p "Enter SENTRY2_NODE_ID (default: 2502df3f2f750f62ca83e0e034f5f6620bcc12de): " SENTRY2_NODE_ID
SENTRY2_NODE_ID=${SENTRY2_NODE_ID:-2502df3f2f750f62ca83e0e034f5f6620bcc12de}
# Prompt for VALIDATOR_NODE_IP with a default value
read -p "Enter VALIDATOR_NODE_IP (default: 192.168.8.100): " VALIDATOR_NODE_IP
VALIDATOR_NODE_IP=${VALIDATOR_NODE_IP:-192.168.8.100}
# Prompt for SENTRY1_NODE_IP with a default value
read -p "Enter SENTRY1_NODE_IP (default: 192.168.8.101): " SENTRY1_NODE_IP
SENTRY1_NODE_IP=${SENTRY1_NODE_IP:-192.168.8.101}
# Prompt for SENTRY2_NODE_IP with a default value
read -p "Enter SENTRY2_NODE_IP (default: 192.168.8.102): " SENTRY2_NODE_IP
SENTRY2_NODE_IP=${SENTRY2_NODE_IP:-192.168.8.102}
echo "Configured MONIKER: $MONIKER"
echo "Configured ACCOUNT: $ACCOUNT"
echo "Configured SENTRY1 NODE ID: $SENTRY1_NODE_ID"
echo "Configured SENTRY2 NODE ID: $SENTRY2_NODE_ID"
echo "Configured VALIDATOR NODE IP: $VALIDATOR_NODE_IP"
echo "Configured SENTRY1 NODE IP: $SENTRY1_NODE_IP"
echo "Configured SENTRY2 NODE IP: $SENTRY2_NODE_IP"

# This function execute command with sudo if user not root
sudo () {
  [[ $EUID = 0 ]] || set -- command sudo "$@"
  "$@"
}
# This function displays a message to contact support and exits the script
contact_support() {
  echo "Please contact support."
  exit 1
}
# This function stop cosmovisor and remove installation directory
install_cleanup() {
  echo "Installation cleanup."
  pkill cosmovisor >/dev/null 2>&1
  rm -rf "${aya_home}" >/dev/null 2>&1
}

# Show welcome message
echo "****************************************************************************"
echo "NODEX Services Aya Testnet \"$CHAIN_ID\" Validator Node Installation Script"
echo "****************************************************************************"

# Set the path to the aya home directory
aya_home=/opt/aya
# Set the path to the current script
path=$(realpath "${BASH_SOURCE:-$0}")
# Set the path to the logfile using the current timestamp
logfile=$(dirname "${path}")/installation_$(date +%s).log
# Set the path to the cosmovisor logfile
cosmovisor_logfile=${aya_home}/logs/cosmovisor.log
# Set the path to the json file with validator registration data
validator_json=${aya_home}/validator.json
# Set the path to the json file with validator registration
en_registration_json=${aya_home}/registration.json
# Set the path to the file with the account name
accountfile=${aya_home}/account
# Clear the contents of the logfile
true >"$logfile"

# Check for previous installation traces
# If present then ask user what to do: try to continue synchronization, start from scratch or cancel
if [[ -d "$aya_home" ]]; then
  echo "Your system already contains an installation directory."
  echo "If you had problems with the installation then you have the following options:"
  echo "- [restart(R)] - erase all existing data and start from scratch"
  echo "- [cancel(C)] - cancel installation"
  echo " WARNING: Erasing wil remove all installation without recovery!"
  echo " Make sure you backed up important files before doing so."
  while true; do
      read -p "What's your choice? [restart(R)/cancel(C)]: " answer
      case $answer in
          [Rr]* ) install_cleanup; break;;
          [Cc]* ) exit;;
          * ) echo "Please answer [restart(R)/cancel(C)].";;
      esac
  done
fi

## If the 'jq' package is not installed, install it
if ! dpkg -s jq >/dev/null 2>&1; then
  echo -e "-- Installing dependencies (jq package)\n"
  sudo apt-get -q install jq -y >/dev/null 2>&1
fi
## If the 'bc' package is not installed, install it
if ! dpkg -s bc >/dev/null 2>&1; then
  echo -e "-- Installing dependencies (bc package)\n"
  sudo apt-get -q install bc -y >/dev/null 2>&1
fi
## If the 'unzip' package is not installed, install it
if ! dpkg -s unzip >/dev/null 2>&1; then
  echo -e "-- Installing dependencies (unzip package)\n"
  sudo apt-get -q install unzip -y >/dev/null 2>&1
fi

# Creating AYA File System
echo "Creating and setting up AYA file system..."
sudo mkdir -p ${aya_home}
sudo chown -R ${USER}:${USER} ${aya_home}
sudo mkdir -p "${aya_home}"/cosmovisor/genesis/bin
sudo mkdir -p "${aya_home}"/backup
sudo mkdir -p "${aya_home}"/logs
sudo mkdir -p "${aya_home}"/config
sudo chown -R ${USER}:${USER} ${aya_home}
sudo apt-get -q install jq -y
mkdir ${HOME}/earthnode_installer
cd ${HOME}/earthnode_installer
sleep 3

# Writing Account Name To AYA Home
echo "$ACCOUNT" > "$accountfile"

# Downloading Source Files
echo "Downloading required files..."
wget https://github.com/max-hontar/aya-preview-binaries/releases/download/v0.4.1/aya_preview_501_installer_2023_09_04.zip
sudo apt-get -q install unzip -y
unzip -o aya_preview_501_installer_2023_09_04.zip

# Check the checksum of the 'ayad' binary against the 'release_checksums' file
# If the checksums do not match, exit the script with an error message
grep "$(sha256sum ayad)" release_checksums 1>/dev/null
if [[ $? -ne 0 ]]; then
  echo "Incorrect checksum of ayad binary"
  exit 1
fi
# Check the checksum of the 'cosmovisor' binary against the 'release_checksums' file
# If the checksums do not match, exit the script with an error message
grep "$(sha256sum cosmovisor)" release_checksums 1>/dev/null
if [[ $? -ne 0 ]]; then
  echo "Incorrect checksum of cosmovisor binary"
  exit 2
fi

echo "--------------------------------------------------"
echo "The following configuration will be used:"
echo "--------------------------------------------------"
echo "CHAIN_ID: ${CHAIN_ID}"
echo "MONIKER: ${MONIKER}"
echo "ACCOUNT: ${ACCOUNT}"
echo "--------------------------------------------------"
echo "RPC Peer Details"
echo "--------------------------------------------------"
echo "RPC_PEERS"
echo "RPC_PEER1: ${SENTRY1_NODE_IP}:${AYA_RPC_PORT}"
echo "RPC_PEER2: ${SENTRY2_NODE_IP}:${AYA_RPC_PORT}"
echo "--------------------------------------------------"
echo "P2P Peer Details"
echo "--------------------------------------------------"
echo "P2P_PEER1: ${SENTRY1_NODE_IP}:${AYA_P2P_PORT}"
echo "P2P_PEER2: ${SENTRY2_NODE_IP}:${AYA_P2P_PORT}"
echo "--------------------------------------------------"
echo "SENTRY 1 NODE ID: ${SENTRY1_NODE_ID}"
echo "SENTRY 2 NODE ID: ${SENTRY2_NODE_ID}"
echo "SENTRY 1 NODE IP: ${SENTRY1_NODE_IP}"
echo "SENTRY 2 NODE IP: ${SENTRY2_NODE_IP}"
echo "VALIDATOR NODE IP: ${VALIDATOR_NODE_IP}"
echo "--------------------------------------------------"
echo "AYA Seed Node Details"
echo "--------------------------------------------------"
echo "AYA_SEED_NODE: ${AYA_SEED_NODE}"
echo "AYA_SEED_URL: ${AYA_SEED_URL}"
echo "--------------------------------------------------"

echo ""

read -r -p "Do you want to continue? [y/N] " response
if ! [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
  exit
fi

# Copying Source Files to Application Directories
echo "Copying AYAD to ${aya_home}..."
cp -f -v "${HOME}/earthnode_installer/ayad" "${aya_home}/cosmovisor/genesis/bin/ayad"
chmod +x "${aya_home}/cosmovisor/genesis/bin/ayad"
echo "Copying COSMOVISOR to ${aya_home}..."
cp -f -v "${HOME}/earthnode_installer/cosmovisor" "${aya_home}/cosmovisor"
chmod +x "${aya_home}/cosmovisor/cosmovisor"

echo "Initialising AYAD (ayad init) ..."
cd "${HOME}/earthnode_installer"
echo "Initializing the validator node ${MONIKER} ..."
# Initialize the node with the specified 'MONIKER'
# If this fails, display an error message and call the 'contact_support()' function to exit
if ! ./ayad init "${MONIKER}" --chain-id $CHAIN_ID --home ${aya_home} >"$logfile" 2>&1; then
  echo "Failed to initialize the node "
  contact_support
fi
echo "Copying the genesis file to the config directory ..."
cp -f -v "${HOME}/earthnode_installer/genesis.json" "${aya_home}/config/genesis.json"
# Create a new operator account and store the JSON output in the 'operator_json' variable
operator_json=$(./ayad keys add "${ACCOUNT}" --output json --home ${aya_home})
# Extract the address from the 'operator_json' variable and store it in the 'operator_address' variable
operator_address=$(echo "$operator_json" | jq '.address' | sed 's/\"//g')
# Display the mnemonic and address of the operator account
echo -e "\n-- [ONLY FOR YOUR EYES] Store this information safely, the mnemonic is the only way to recover your account. \n"
echo "$operator_json" | jq -M

# Create symbolic links for the 'ayad' and 'cosmovisor' binaries
sudo ln -s ${aya_home}/cosmovisor/current/bin/ayad /usr/local/bin/ayad >/dev/null 2>&1
sudo ln -s ${aya_home}/cosmovisor/cosmovisor /usr/local/bin/cosmovisor >/dev/null 2>&1

# Obtaining Validators Node ID
~/earthnode_installer/ayad tendermint show-node-id --home /opt/aya > $aya_home/node-id.txt
# Execute the command to get the node ID
VALIDATOR_NODE_ID=$(~/earthnode_installer/ayad tendermint show-node-id --home $aya_home)
# Display the node ID and instructions for the user
echo "-------------------------------------------------------"
echo "VALIDATOR NODE ID: $VALIDATOR_NODE_ID"
echo "-------------------------------------------------------"
echo "Please copy the above NODE ID and paste it into the sentry node update script on both servers."
echo "Press any key to continue once you've completed this task..."
# Wait for user input to continue
read -n1 -s
echo "Continuing the script..."

# Creating the initial sycnhonrization block metrics
echo "Creating the initial sycnhonrization block metrics"
# Value equal to snapshot creation interval
INTERVAL=100
# Get latest block height on chain
LATEST_HEIGHT=$(curl -s "${SENTRY1_NODE_IP}:${AYA_RPC_PORT}/block" | jq -r .result.block.header.height)
if [ -z "${LATEST_HEIGHT}" ]; then
  echo "Failed to query latest block height over RPC request."
  contact_support
fi
# Get a bit older block height, to validate snapshot over it
BLOCK_HEIGHT=$((($((LATEST_HEIGHT / INTERVAL)) - 1) * INTERVAL + $((INTERVAL / 2))))
# Get block hash for "safe" block height
TRUST_HASH=$(curl -s "${SENTRY1_NODE_IP}:${AYA_RPC_PORT}/block?height=${BLOCK_HEIGHT}" | jq -r .result.block_id.hash)
if [ -z "${TRUST_HASH}" ]; then
  echo "Failed to query trusted block hash over RPC request."
  contact_support
fi
echo "Snapshot will start at block height ${BLOCK_HEIGHT} with interval ${INTERVAL}"

echo "Enable StateSync module, to speed up node initial bootstrap"
# Enable StateSync module, to speed up node initial bootstrap
sed -i -E "s|^(enable[[:space:]]+=[[:space:]]+).*$|\1true|" "${aya_home}"/config/config.toml
# Set available RPC servers (at least two) required for light client snapshot verification
sed -i -E "s|^(rpc_servers[[:space:]]+=[[:space:]]+).*$|\1\"${SENTRY1_NODE_IP}:${AYA_RPC_PORT},${SENTRY2_NODE_IP}:${AYA_RPC_PORT}\"|" "${aya_home}"/config/config.toml
# Set "safe" trusted block height
sed -i -E "s|^(trust_height[[:space:]]+=[[:space:]]+).*$|\1$BLOCK_HEIGHT|" "${aya_home}"/config/config.toml
# Set "safe" trusted block hash
sed -i -E "s|^(trust_hash[[:space:]]+=[[:space:]]+).*$|\1\"$TRUST_HASH\"|" "${aya_home}"/config/config.toml
# Set trust period, should be ~2/3 unbonding time (3 weeks for preview network)
sed -i -E "s|^(trust_period[[:space:]]+=[[:space:]]+).*$|\1\"302h0m0s\"|" "${aya_home}"/config/config.toml

# Temporary fix for https://github.com/cosmos/cosmos-sdk/issues/13766, will be removed after binary rebuild over Cosmos SDK v0.46.7 or above
# Set snapshot interval >0 to activate snapshot manager
sed -i -E 's|^(snapshot-interval[[:space:]]+=[[:space:]]+).*$|\1999999999999|' ${aya_home}/config/app.toml
# Set the log level to 'error' in the 'config.toml' file
sed -i "s/log_level = \"info\"/log_level = \"error\"/g" "${aya_home}"/config/config.toml

# Get SENTRY NODE 1 ID
SENTRY1_NODE_ID=$(curl -s "${SENTRY1_NODE_IP}:${AYA_RPC_PORT}/status" | jq -r .result.node_info.id)
if [ -z "${SENTRY1_NODE_ID}" ]; then
  echo "Failed to query SENTRY NODE 1 ID over RPC request."
  contact_support
fi
# Get SENTRY NODE 2 ID
SENTRY2_NODE_ID=$(curl -s "${SENTRY2_NODE_IP}:${AYA_RPC_PORT}/status" | jq -r .result.node_info.id)
if [ -z "${SENTRY2_NODE_ID}" ]; then
  echo "Failed to query SENTRY NODE 2 ID over RPC request."
  contact_support
fi
# Get AYA SEED NODE ID
AYA_SEED_NODE_ID=$(curl -s "${AYA_SEED_NODE}:${AYA_RPC_PORT}/status" | jq -r .result.node_info.id)
if [ -z "${AYA_SEED_NODE_ID}" ]; then
  echo "Failed to query AYA_SEED_NODE ID over RPC request."
  contact_support
fi

# Set the seed node in the 'config.toml' file
sed -i -E "s|^(seeds[[:space:]]+=[[:space:]]+).*$|\1\"${AYA_SEED_NODE_ID}@${AYA_SEED_NODE}:${AYA_P2P_PORT}\"|" "${aya_home}"/config/config.toml
# Set the seed nodes in the 'config.toml' file
sed -i -E "s|^(persistent_peers[[:space:]]+=[[:space:]]+).*$|\1\"${SENTRY1_NODE_ID}@${AYA_HOST1}:${AYA_P2P_PORT1},${SENTRY2_NODE_ID}@${AYA_HOST2}:${AYA_P2P_PORT2}\"|" "${aya_home}"/config/config.toml
# Replace GRPC port to not overlap with standard Prometheus port
sed -i "s/:9090/:29090/g" "${aya_home}"/config/app.toml
# Change gas price units for our network
sed -i 's/0stake/0uswmt/g' "${aya_home}"/config/app.toml

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
sleep 3
echo "Modifying the config.toml parameters"
sleep 3
# Declaring an associative array with composite keys
declare -A sections
sections["global,log_level,1"]="error"
sections["p2p,pex,0"]="false"
sections["p2p,addr_book_strict,0"]="false"
sections["p2p,upnp,0"]="false"
sections["p2p,max_num_outbound_peers,0"]="10"
sections["p2p,max_num_inbound_peers,0"]="10"
sections["p2p,persistent_peers_max_dial_period,1"]="0s"
sections["p2p,persistent_peers,1"]="${SENTRY1_NODE_ID}@${SENTRY1_NODE_IP}:${AYA_P2P_PORT},${SENTRY2_NODE_ID}@${SENTRY2_NODE_IP}:${AYA_P2P_PORT}"
sections["p2p,unconditional_peer_ids,1"]="${SENTRY1_NODE_ID},${SENTRY2_NODE_ID}"
sections["rpc,laddr,1"]="tcp://0.0.0.0:26657"
sections["rpc,experimental_websocket_write_buffer_size,0"]="300"
# Iterate over each composite key and apply the changes
for compositeKey in "${!sections[@]}"; do
    IFS=',' read -r section key quote <<< "$compositeKey"
    value="${sections[$compositeKey]}"
    update_config "${aya_home}"/config/config.toml "$section" "$key" "$value" "$quote"
done
sleep 3

# Declaring another associative array for the app.toml changes
declare -A sections2
sections2["api,enable,0"]="true"
# Iterate over each composite key for the app.toml changes and apply the updates
for compositeKey in "${!sections2[@]}"; do
    IFS=',' read -r section key quote <<< "$compositeKey"
    value="${sections2[$compositeKey]}"
    update_config "${aya_home}"/config/app.toml "$section" "$key" "$value" "$quote"
done

# Export some environment variables
export DAEMON_NAME=ayad
export DAEMON_HOME="${aya_home}"
export DAEMON_DATA_BACKUP_DIR="${aya_home}"/backup
export DAEMON_RESTART_AFTER_UPGRADE=true
export DAEMON_ALLOW_DOWNLOAD_BINARIES=true

# Set soft file descriptors limit for session (default: 1024)
ulimit -Sn 4096

echo "Starting cosmovisor to start the snapshot process. You can check logs at ${cosmovisor_logfile}"
# Start 'cosmovisor'. Append output to log file. Run in the background so script can continue.
"${aya_home}"/cosmovisor/cosmovisor run start --home ${aya_home} &>>"${cosmovisor_logfile}" &
PID=$!
echo "Captured PID: $PID"

# Verify 'cosmovisor' process is running.
# If its not running display status in terminal and log file. Proceed to call 'contact_support()' function.
if ! pgrep cosmovisor >/dev/null 2>&1; then
  echo "Cosmovisor not running." | tee -a "$logfile"
  contact_support
fi

# Get the address of the validator
validator_address=$(${aya_home}/cosmovisor/genesis/bin/ayad tendermint show-address --home ${aya_home})
# Use 'jq' to create a JSON object with the 'MONIKER', 'operator_address' and 'validator_address' fields
jq --arg key0 'moniker' \
   --arg value0 "$MONIKER" \
   --arg key1 'operator_address' \
   --arg value1 "$operator_address" \
   --arg key2 'validator_address' \
   --arg value2 "$validator_address" \
   '. | .[$key0]=$value0 | .[$key1]=$value1 | .[$key2]=$value2' \
 <<<'{}' | tee $en_registration_json

echo -e "\n-- Now we have to wait until your node is up to date... It will take a while!\n"

# Sleep for 30 seconds
sleep 30

# Set authorized to false
authorized=false
# While authorized is false, do the following:
while [ "$authorized" = "false" ]; do
   # Get node status
   node_status=$(./ayad status --home ${aya_home})
   #get catching up
   catching_up=$(echo "$node_status"| jq '.SyncInfo.catching_up' | sed 's/"//g')
   if [ $catching_up = false ]; then
     authorized=true
   else
    # Get first chain block time
    chain_first_block_time=$(echo "$node_status"| jq '.SyncInfo.earliest_block_time' | sed 's/"//g')
    # Get last received block time
    chain_current_block_time=$(echo "$node_status"| jq '.SyncInfo.latest_block_time' | sed 's/"//g')
    # Get last received block height
    chain_current_block_height=$(echo "$node_status" | jq '.SyncInfo.latest_block_height' | sed 's/"//g')
    # Calculate current chain state age in seconds
    chain_current_age=$(( $(date +%s -d "$chain_current_block_time") - $(date +%s -d "$chain_first_block_time") ))
    # Calculate chain age up to now in seconds
    chain_full_age=$(( $(date +%s) - $(date +%s -d "$chain_first_block_time") ))
    # Calculate chain relative synchronization progress
    sync_progress=$((100*100*chain_current_age/chain_full_age))
    # Correct synchronization progress edge case for start
    if [ "$sync_progress" -eq "0" ]; then sync_progress="0000"; fi
    # If the balance of the operator address not contain 'uswmt' denomination, print a message and sleep for 60 seconds
    echo -e "\e[1A\e[K Still syncing... Progress: ${sync_progress:0:-2}.${sync_progress: -2}% Height: ${chain_current_block_height} Last update: $(date)"
    sleep 10
  fi
done

echo "Killing the synchonisation job..."
kill $PID

# Remove temporary fix for https://github.com/cosmos/cosmos-sdk/issues/13766
# Set snapshot interval back to default (0) after installation
sed -i -E 's|^(snapshot-interval[[:space:]]+=[[:space:]]+).*$|\10|' ${aya_home}/config/app.toml
# Disable StateSync module to avoid possible problems on node restart
sed -i -E "s|^(enable[[:space:]]+=[[:space:]]+).*$|\1false|" "${aya_home}"/config/config.toml

echo -e "\n-- All up to date!\n"
echo -e "\n-- Welcome to Aya sidechain :D \n\n"

# Create systemd service file that describes the background service running the 'cosmovisor' daemon.
echo "Configuring your node to start on server startup"
sudo tee /etc/systemd/system/cosmovisor.service > /dev/null <<EOF
# Start the 'cosmovisor' daemon and append any output to the 'aya.log' file
# Create a Systemd service file for the 'cosmovisor' daemon
[Unit]
Description=Aya Node
After=network-online.target

[Service]
User=$USER
# Start the 'cosmovisor' daemon with the 'run start' command and write output to 'aya.log' file
ExecStart=$(which cosmovisor) run start --home "${aya_home}"
# Restart the service if it fails
Restart=always
# Restart the service after 3 seconds if it fails
RestartSec=3
# Set the maximum number of file descriptors
LimitNOFILE=4096

# Set environment variables for data backups, automatic downloading of binaries, and automatic restarts after upgrades
Environment="DAEMON_NAME=ayad"
Environment="DAEMON_HOME=${aya_home}"
Environment="DAEMON_DATA_BACKUP_DIR=${aya_home}/backup"
Environment="DAEMON_ALLOW_DOWNLOAD_BINARIES=true"
Environment="DAEMON_RESTART_AFTER_UPGRADE=true"

[Install]
# Start the service on system boot
WantedBy=multi-user.target
EOF

# Reload the Systemd daemon
sudo systemctl daemon-reload
# Enable the 'cosmovisor' service to start on system boot
sudo systemctl enable cosmovisor
sudo systemctl start cosmovisor

echo "Installing the live monitoring software"
sleep 3
cd ${HOME}
mkdir -p nodebase-tools
cd nodebase-tools
wget -O ayaview.zip https://github.com/nodebasewm/download/blob/main/ayaview.zip?raw=true
unzip -o ayaview.zip
echo "Starting Ayaview so you can see if it is working"
echo "Ayaview will run for one minute and then the system will restart"
${HOME}/nodebase-tools/ayaview --config /opt/aya/config/config.toml &
sleep 60

echo "Set Ayaview to run when ${USER} logs in ..."
echo "~/nodebase-tools/ayaview --config /opt/aya/config/config.toml" >> ~/.bashrc
sleep 30

echo "Validator Installation Is Complete. Rebooting ..."
sleep 5
sudo reboot
