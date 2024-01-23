#!/bin/bash

# Log file location
LOG_DIR="/logs"
LOG_FILE="${LOG_DIR}/cloud-init-disable.log"

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

# Disable Cloud-Init's network configuration capabilities
write_log "Disabling Cloud-Init network configuration"
echo "network: {config: disabled}" > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

# Disable Cloud-Init
write_log "Disabling Cloud-Init"
touch /etc/cloud/cloud-init.disabled

# Logging completion
write_log "Cloud-Init disabled successfully"
