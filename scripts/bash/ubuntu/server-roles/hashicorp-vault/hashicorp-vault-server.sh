#!/bin/bash

: '
.SYNOPSIS
This script executes a series of scripts for server baseline configuration for a HashiCorp Vault Server.

.DESCRIPTION
The script performs the following actions:
- Ensures the log directory exists and creates a log file.
- Disables Cloud-Init.
- Verifies if the user has sudo privileges, prompting for a password if necessary.
- Executes a predefined list of scripts for server configuration, logging the output.
- Performs a full system upgrade, removes unnecessary packages, and optionally reboots.

.NOTES
Version:            1.3
Author:             Darren Pilkington
Modification Date:  20-04-2025
'

# Default configuration scripts directory
DEFAULT_CONFIG_SCRIPTS_DIR="/source-files/github/monorepo/scripts/bash/ubuntu"

# Default log directory
DEFAULT_LOG_DIR="/logs"

# Allow overriding defaults via environment variables
CONFIG_SCRIPTS_DIR="${CONFIG_SCRIPTS_DIR:-$DEFAULT_CONFIG_SCRIPTS_DIR}"
LOG_DIR="${LOG_DIR:-$DEFAULT_LOG_DIR}"

# Define log file
LOG_FILE="$LOG_DIR/server-baseline-$(date '+%Y%m%d').log"

# Function to write log with timestamp
write_log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | sudo tee -a "$LOG_FILE"
}

# Create log directory if it doesn’t exist
if [ ! -d "$LOG_DIR" ]; then
    sudo mkdir -p "$LOG_DIR" || { echo "Failed to create $LOG_DIR"; exit 1; }
    write_log "Created log directory: $LOG_DIR"
fi

# Create or ensure log file exists
sudo touch "$LOG_FILE" || { echo "Failed to create $LOG_FILE"; exit 1; }

# Log script start
write_log "Script started on $(date)"

# Inform user about sudo requirement
echo "This script requires sudo privileges. You may be prompted for your password."

# Confirmation prompt to proceed
read -p "Do you want to proceed with the server baseline configuration? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    write_log "User chose not to proceed. Exiting."
    exit 0
fi
write_log "User confirmed to proceed with configuration."

# Check for sudo privileges
if ! sudo -n true 2>/dev/null; then
    write_log "Sudo requires a password. Prompting for sudo credentials."
    sudo -v || { write_log "Failed to obtain sudo credentials."; exit 1; }
else
    write_log "Sudo is available without a password."
fi

# Disable Cloud-Init
write_log "Disabling Cloud-Init"
sudo touch /etc/cloud/cloud-init.disabled || { write_log "Failed to disable Cloud-Init"; exit 1; }
write_log "Cloud-Init disabled successfully"

# List of scripts to run (relative to CONFIG_SCRIPTS_DIR)
SCRIPTS_TO_RUN=(
    "configuration/apply-branding.sh"
    "packages/install-webmin.sh"
    "configuration/extend-disks.sh"
    "configuration/disable-ipv6.sh"
    "configuration/dns-default-gateway.sh"
    "configuration/setup-iptables.sh"
    "configuration/disable-cloud-init.sh"
    "configuration/create-openssl-root-cert.sh"
    "packages/install-hashicorp-vault.sh"
)

# Execute each script
for script in "${SCRIPTS_TO_RUN[@]}"; do
    script_path="${CONFIG_SCRIPTS_DIR}/${script}"

    # Verify script exists
    if [ -f "$script_path" ]; then
        write_log "Processing $script_path"

        # Make script executable
        write_log "Changing permissions for $script_path"
        sudo chmod +x "$script_path" || { write_log "Failed to set permissions for $script_path"; exit 1; }

        # Run the script with sudo
        write_log "Executing $script_path"
        if sudo "$script_path"; then
            write_log "$script executed successfully"
        else
            write_log "Error: Failed to execute $script_path"
            exit 1
        fi
    else
        write_log "Error: Script $script_path does not exist"
        exit 1
    fi
done

write_log "All specified scripts executed successfully"

# Check Ubuntu version before adding repository
UBUNTU_VERSION=$(lsb_release -cs)
if [ "$UBUNTU_VERSION" = "jammy" ]; then
    write_log "Adding jammy-updates repository"
    sudo add-apt-repository -y "deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse" || { write_log "Failed to add repository"; exit 1; }
    write_log "jammy-updates repository added successfully"
else
    write_log "Skipping repository addition (not Ubuntu Jammy)"
fi

# Update and upgrade system
write_log "Updating package lists"
sudo DEBIAN_FRONTEND=noninteractive apt update -y || { write_log "Failed to update package lists"; exit 1; }
sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y || { write_log "Failed to upgrade packages"; exit 1; }
sudo DEBIAN_FRONTEND=noninteractive apt autoremove -y || { write_log "Failed to remove unused packages"; exit 1; }
sudo DEBIAN_FRONTEND=noninteractive apt autoclean -y || { write_log "Failed to clean package cache"; exit 1; }
write_log "System updated successfully"

# Final success confirmation
write_log "All configuration steps completed successfully on $(date)"

# Reboot prompt
read -p "Do you want to reboot now? (y/N): " reboot_now
if [[ "$reboot_now" =~ ^[Yy]$ ]]; then
    write_log "User chose to reboot now."
    sudo reboot
else
    write_log "User chose not to reboot now. Please reboot manually when ready."
fi