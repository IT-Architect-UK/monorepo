#!/bin/bash

: '
.SYNOPSIS
This script installs or upgrades Prometheus Node Exporter on Ubuntu Linux servers.

.DESCRIPTION
- This script checks if Prometheus Node Exporter is already installed.
- If not installed, it installs the latest version.
- If already installed, it upgrades to the latest version.
- It logs each step of the process.

.NOTES
Version:            1.0
Author:             Darren Pilkington
Modification Date:  04-06-2024
'

# Log file location
LOG_DIR="/logs"
LOG_FILE="${LOG_DIR}/install-prometheus-node-exporter-ubuntu.log"

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

# Check if node_exporter is installed
check_node_exporter() {
    if command -v node_exporter &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Install or upgrade node_exporter
install_or_upgrade_node_exporter() {
    # Download the latest version
    write_log "Downloading the latest version of Prometheus Node Exporter..."
    latest_version=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep tag_name | cut -d '"' -f 4)
    wget https://github.com/prometheus/node_exporter/releases/download/${latest_version}/node_exporter-${latest_version}.linux-amd64.tar.gz

    # Extract the files
    tar xvf node_exporter-${latest_version}.linux-amd64.tar.gz
    cd node_exporter-${latest_version}.linux-amd64

    # Move the binary to /usr/local/bin
    sudo mv node_exporter /usr/local/bin/
    write_log "Moved node_exporter binary to /usr/local/bin/"

    # Create a systemd service file
    write_log "Creating systemd service file for node_exporter..."
    sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter

[Service]
User=node_exporter
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=default.target
EOF

    # Reload systemd and start node_exporter
    sudo systemctl daemon-reload
    sudo systemctl start node_exporter
    sudo systemctl enable node_exporter
    write_log "Node Exporter service started and enabled."
}

# Main script execution
write_log "Starting the installation script for Prometheus Node Exporter..."

if check_node_exporter; then
    write_log "Prometheus Node Exporter is already installed. Upgrading to the latest version..."
else
    write_log "Prometheus Node Exporter is not installed. Installing the latest version..."
fi

install_or_upgrade_node_exporter

write_log "Installation or upgrade of Prometheus Node Exporter completed."
