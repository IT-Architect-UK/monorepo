#!/bin/bash

# Log file location
LOG_DIR="/logs"
LOG_FILE="${LOG_DIR}/aya-testnet-node-configuration.log"

# Ensure log directory exists
if [ ! -d "$LOG_DIR" ]; then
    sudo mkdir -p "$LOG_DIR"
    echo "Created log directory: ${LOG_DIR}"
fi

# Function to write log with timestamp
write_log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | sudo tee -a "$LOG_FILE"
}

write_log "Downloading AYA TestNet Node Source Code"
cd /home/${USER}
mkdir -p aya-node/target/release
cd aya-node
wget https://github.com/worldmobilegroup/aya-node/releases/download/devnet-v.0.2.0/wm-devnet-chainspec.json
wget -P target/release https://github.com/worldmobilegroup/aya-node/releases/download/devnet-v.0.2.0/aya-node
chmod +x target/release/aya-node

# Creating Key Rotation Script
write_log "Creating Key Rotation Script"
# Create the directory if it doesn't exist
mkdir -p utils/session_key_tools
# Create the split_session_key.sh script with the required content
cat << 'EOF' > utils/session_key_tools/split_session_key.sh
#!/usr/bin/env bash
set -e
if [[ $# -ne 1 ]]; then
    echo "Please provide a session key as parameter to the script!"
    exit 1
else
    SESSION_KEY=$1
    if [[ ! ${#SESSION_KEY} -eq 194 ]]; then
        echo "Please provide a valid session key!"
        exit 1
    fi
fi
echo "------------------------------------"
echo "Your session keys:"
echo AURA_SESSION_KEY=${SESSION_KEY:0:66}
echo GRANDPA_SESSION_KEY=0x${SESSION_KEY:66:64}
echo IM_ONLINE_SESSION_KEY=0x${SESSION_KEY:130:64}
echo "------------------------------------"
EOF
# Make the script executable
chmod +x utils/session_key_tools/split_session_key.sh
echo "Script created and made executable successfully!"

# Setting Up SYSTEMD
write_log "Setting Up SYSTEMD"
export AYA_HOME=/home/${USER}/aya-node
sudo bash -c "echo 'export AYA_HOME=/home/${USER}/aya-node' >> /etc/bash.bashrc"
echo '#!/usr/bin/env bash' > start_aya_validator.sh
echo "${AYA_HOME}/target/release/aya-node \
    --base-path ${AYA_HOME}/data/validator \
    --validator \
    --chain ${AYA_HOME}/wm-devnet-chainspec.json \
    --port 30333 \
    --rpc-port 9944 \
    --rpc-cors all \
    --log info \
    --prometheus-external \
    --bootnodes /dns/devnet-rpc.worldmobilelabs.com/tcp/30340/ws/p2p/12D3KooWRWZpEJygTo38qwwutM1Yo7dQQn8xw1zAAWpfMiAqbmyK" >> start_aya_validator.sh
sudo chmod +x ./start_aya_validator.sh

# Creating the SYSTEMD Service
write_log "Creating the SYSTEMD Service"
sudo tee /etc/systemd/system/aya-node.service > /dev/null <<EOF
#Start the Aya validator
[Unit]
Description=AyA Node
After=network.target

[Service]
WorkingDirectory=${AYA_HOME}
ExecStart="${AYA_HOME}"/start_aya_validator.sh
User=${USER}
Restart=always
RestartSec=90
#Set the maximum number of file descriptors
LimitNOFILE=10000

[Install]
WantedBy=multi-user.target
EOF

# Enable the AYA Node Service
write_log "Enabling the AYA Node Service"
sudo systemctl enable aya-node.service
