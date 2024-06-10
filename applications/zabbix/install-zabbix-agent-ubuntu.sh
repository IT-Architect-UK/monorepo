#!/bin/bash

: '
.SYNOPSIS
This script installs the latest Zabbix agent v2 on an Ubuntu operating system.

.DESCRIPTION
The script performs the following actions:
- Checks for an active internet connection.
- Installs the Zabbix repository.
- Installs the Zabbix Agent v2 and plugins.
- Configures the Zabbix Agent v2.
- Starts and enables the Zabbix Agent v2 service.
- Verifies the installation and ensures the service is running and the TCP port is listening.
- Writes installation actions to a log file.

.NOTES
Version:            1.0
Author:             Darren Pilkington
Modification Date:  31-05-2024
'

# Function to log messages with timestamp
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | sudo tee -a "$LOG_FILE"
}

# Log file location
LOG_DIR="/var/log/zabbix"
LOG_FILE="${LOG_DIR}/install-zabbix-agent-$(date +'%Y%m%d-%H%M%S').log"

# Ensure log directory exists
if [ ! -d "$LOG_DIR" ]; then
    sudo mkdir -p "$LOG_DIR"
    echo "Created log directory: ${LOG_DIR}"
fi

# Check if user is root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root."
    exit 1
fi

# Prompt for Server IP if not provided as an argument
if [ -z "$1" ]; then
    read -p "Please enter the Zabbix server IP address: " ServerIP
else
    ServerIP="$1"
fi

# Prompt for Server Name if not provided as an argument
if [ -z "$2" ]; then
    read -p "Please enter the Zabbix server name: " ServerName
else
    ServerName="$2"
fi

# Get the FQDN of the computer and capitalize it
FQDN=$(hostname -f | tr '[:lower:]' '[:upper:]')
if [ -z "$FQDN" ]; then
    echo "Failed to retrieve the FQDN of the computer."
    exit 1
fi

echo "Installing Zabbix Agent v2 ...."
echo "Configuring Script Log Settings."

log_message "Log file path set to $LOG_FILE."

# Check for active internet connection
if ! ping -c 2 8.8.8.8 > /dev/null 2>&1; then
    log_message "No active internet connection found. Please ensure you are connected to the internet before running this script."
    exit 1
fi

log_message "Active internet connection detected. Continuing with script ..."

# Install Zabbix repository
log_message "Adding Zabbix repository..."
wget -q https://repo.zabbix.com/zabbix/7.0/ubuntu/pool/main/z/zabbix-release/zabbix-release_7.0-1+ubuntu22.04_all.deb
if [ -f zabbix-release_7.0-1+ubuntu22.04_all.deb ]; then
    sudo dpkg -i zabbix-release_7.0-1+ubuntu22.04_all.deb
    sudo apt update
else
    log_message "Failed to download Zabbix repository package. Exiting script."
    exit 1
fi

# Install Zabbix agent and plugins
log_message "Installing Zabbix Agent v2 and plugins..."
if sudo apt install zabbix-agent2 zabbix-agent2-plugin-* -y; then
    log_message "Zabbix Agent v2 and plugins installed successfully."
else
    log_message "Failed to install Zabbix Agent v2 and plugins. Exiting script."
    exit 1
fi

# Configure Zabbix agent
log_message "Configuring Zabbix Agent v2..."
if [ -f /etc/zabbix/zabbix_agent2.conf ]; then
    sudo sed -i "s/^Server=.*/Server=$ServerName,$ServerIP/" /etc/zabbix/zabbix_agent2.conf
    sudo sed -i "s/^ServerActive=.*/ServerActive=$ServerName,$ServerIP/" /etc/zabbix/zabbix_agent2.conf
    sudo sed -i "s/^Hostname=.*/Hostname=$FQDN/" /etc/zabbix/zabbix_agent2.conf
else
    log_message "Zabbix agent configuration file not found. Exiting script."
    exit 1
fi

# Start and enable Zabbix agent service
log_message "Starting and enabling Zabbix Agent v2 service..."
if sudo systemctl restart zabbix-agent2 && sudo systemctl enable zabbix-agent2; then
    log_message "Zabbix agent service started and enabled successfully."
else
    log_message "Failed to start or enable Zabbix agent service. Exiting script."
    exit 1
fi

# Verify the Zabbix agent service is running
if systemctl is-active --quiet zabbix-agent2; then
    log_message "Zabbix agent service is running."
else
    log_message "Zabbix agent service is not running. Attempting to start the service..."
    sudo systemctl start zabbix-agent2
    if systemctl is-active --quiet zabbix-agent2; then
        log_message "Zabbix agent service started successfully."
    else
        log_message "Failed to start Zabbix agent service. Exiting script."
        exit 1
    fi
fi

# Verify the TCP port 10050 is listening
if ss -tuln | grep -q ':10050'; then
    log_message "TCP port 10050 is listening."
else
    log_message "TCP port 10050 is not listening. Please check the Zabbix agent configuration."
    exit 1
fi

log_message "Zabbix agent installation and verification completed successfully."
echo "Zabbix agent installation and verification completed successfully."
