#!/bin/bash

: '
.SYNOPSIS
This script installs or upgrades Prometheus Node Exporter on Ubuntu Linux servers.

.DESCRIPTION
- This script checks if Prometheus Node Exporter is already installed.
- If not installed, it installs the latest version.
- If already installed, it upgrades to the latest version.
- It logs each step of the process.
- It verifies the service is running and the port is listening at the end.

.NOTES
Version:            1.0
Author:             Darren Pilkington
Modification Date:  04-06-2024
'

# Log file location
LOG_DIR="/logs"
LOG_FILE="${LOG_DIR}/install-node-exporter.log"

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

# Create node_exporter user if it doesn't exist
create_node_exporter_user() {
    if ! id -u node_exporter > /dev/null 2>&1; then
        sudo useradd --no-create-home --shell /bin/false node_exporter
        write_log "Created node_exporter user."
    fi
}

# Install or upgrade node_exporter
install_or_upgrade_node_exporter() {
    # Get the latest version URL from GitHub API
    write_log "Fetching the latest version URL of Prometheus Node Exporter..."
    latest_url=$(curl -s https://api.github.com/repos/prometheus/node_exporter/releases/latest | grep "browser_download_url.*linux-amd64.tar.gz" | cut -d '"' -f 4)

    if [ -z "$latest_url" ]; then
        write_log "Error: Unable to fetch the latest version URL of Prometheus Node Exporter."
        exit 1
    fi

    # Download the latest version
    write_log "Downloading Prometheus Node Exporter from ${latest_url}..."
    wget "$latest_url" -O node_exporter.tar.gz

    if [ $? -ne 0 ]; then
        write_log "Error: Download failed."
        exit 1
    fi

    # Extract the files
    tar xvf node_exporter.tar.gz
    cd node_exporter-*.linux-amd64 || { write_log "Error: Extraction failed."; exit 1; }

    # Move the binary to /usr/local/bin
    sudo mv node_exporter /usr/local/bin/
    sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter
    write_log "Moved node_exporter binary to /usr/local/bin/"

    # Create a systemd service file
    write_log "Creating systemd service file for node_exporter..."
    sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
ExecStart=/usr/local/bin/node_exporter
Restart=always

[Install]
WantedBy=default.target
EOF

    # Reload systemd and start node_exporter
    sudo systemctl daemon-reload
    sudo systemctl start node_exporter
    sudo systemctl enable node_exporter
    write_log "Node Exporter service started and enabled."
}

# Verify the service is running and the port is listening
verify_service() {
    write_log "Verifying Node Exporter service status..."
    if systemctl is-active --quiet node_exporter; then
        write_log "Node Exporter service is running."
    else
        write_log "Node Exporter service is not running. Checking journal logs..."
        sudo journalctl -u node_exporter | tail -n 20 | sudo tee -a "$LOG_FILE"
        exit 1
    fi

    write_log "Verifying Node Exporter is listening on port 9100..."
    if sudo netstat -tuln | grep -q ":9100"; then
        write_log "Node Exporter is listening on port 9100."
    else
        write_log "Node Exporter is not listening on port 9100."
        exit 1
    fi
}

# Main script execution
write_log "Starting the installation script for Prometheus Node Exporter..."

if check_node_exporter; then
    write_log "Prometheus Node Exporter is already installed. Upgrading to the latest version..."
else
    write_log "Prometheus Node Exporter is not installed. Installing the latest version..."
fi

create_node_exporter_user
install_or_upgrade_node_exporter

write_log "Installation or upgrade of Prometheus Node Exporter completed."

verify_service

write_log "Verification of Prometheus Node Exporter service completed successfully."
