#!/bin/bash

# Log file location
LOG_DIR="/logs"
LOG_FILE="${LOG_DIR}/aya-testnet-node-deploy.log"

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

# Start logging
write_log "Starting Cloud-Init disable process"

# Disable Cloud-Init
write_log "Disabling Cloud-Init"
sudo touch /etc/cloud/cloud-init.disabled
write_log "Cloud-Init disabled successfully"

# Create 'wmt' User
username="wmt"
write_log "Creating user $username"
sudo useradd -m $username --disabled-password
sudo usermod -aG sudo $username
echo "$username ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$username
write_log "User $username created successfully with sudo privileges without password"

# Configure Firewall - Allow P2P Port TCP 30333
write_log "Configuring firewall"
sudo iptables -A INPUT -p tcp --dport 30333 -j ACCEPT
# Save the rules
if sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null; then
    write_log "IPTables rules saved successfully."
else
    write_log "Error occurred while saving IPTables rules."
    exit 1
fi

# Switch to the 'wmt' user and run the remaining commands as this user
sudo -i -u $username bash << EOF

EOF

# Logging completion
write_log "AYA TestNet node deployment script completed"
write_log "Rebooting the system to apply changes"
sudo reboot