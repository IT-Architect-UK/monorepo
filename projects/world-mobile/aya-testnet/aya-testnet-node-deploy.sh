#!/bin/bash

# Log file location
LOG_DIR="/logs"
LOG_FILE="${LOG_DIR}/aya-testnet-node-deploy.log"

# Ensure log directory exists
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR"
    echo "Created log directory: ${LOG_DIR}"
fi

# Function to write log with timestamp
write_log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

# Start logging
write_log "Starting Cloud-Init disable process"

# Disable Cloud-Init
write_log "Disabling Cloud-Init"
sudo touch /etc/cloud/cloud-init-disabled
write_log "Cloud-Init disabled successfully"

# Install AYA TestNet Dependencies
write_log "Installing AYA TestNet Dependencies"
sudo apt update && sudo apt upgrade
sudo apt install -y curl

# Configure Firewall - Allow P2P Port TCP 30333
sudo iptables -A INPUT -p tcp --dport 30333 -j ACCEPT
# Save the rules
echo "Saving IPTables rules..."
if sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null; then
    echo "IPTables rules saved successfully."
else
    echo "Error occurred while saving IPTables rules."
    exit 1
fi

# Logging completion
write_log "Cloud-Init disabled successfully"
