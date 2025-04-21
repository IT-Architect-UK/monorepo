#!/bin/bash

: '
.SYNOPSIS
This script executes a series of scripts for server baseline configuration for a Docker Swarm Node.

.DESCRIPTION
The script performs the following actions:
- Ensures the log directory exists and creates a log file.
- Disables Cloud-Init.
- Verifies if the user has sudo privileges without requiring a password.
- Executes a predefined list of scripts for server configuration, logging the output.
- Performs a full system upgrade, removes unnecessary packages, and reboots.

.NOTES
Version:            1.0
Author:             Darren Pilkington
Modification Date:  20-04-2025
'

# Define the scripts directory
SCRIPTS_DIR="/source-files/github/monorepo/scripts/bash/ubuntu"

# Define log file name and directory
LOG_DIR="/logs"
LOG_FILE="$LOG_DIR/server-baseline-$(date '+%Y%m%d').log"

# Create Logs Directory and Log File
mkdir -p "$LOG_DIR"
sudo touch "$LOG_FILE"

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

# Log file location
LOG_FILE="$LOG_DIR/server-baseline-$(date '+%Y%m%d').log"

# Disable Cloud-Init
write_log "Disabling Cloud-Init"
sudo touch /etc/cloud/cloud-init.disabled
write_log "Cloud-Init disabled successfully"

{
    echo "Script started on $(date)"

    # Verify sudo privileges without password
    if ! sudo -n true 2>/dev/null; then
        echo "Error: User does not have sudo privileges or requires a password for sudo."
        exit 1
    fi

    # List of scripts to run
    SCRIPTS_TO_RUN=(
        "configuration/apply-branding.sh"
        "packages/install-webmin.sh"
        "configuration/extend-disks.sh"
        "configuration/disable-ipv6.sh"
        "configuration/dns-default-gateway.sh"
        "configuration/setup-iptables.sh"
        "configuration/disable-cloud-init.sh"
        "configuration/mount-nfs-volume.sh"
        "packages/install-docker-and-docker-compose.sh"
    )

    for script in "${SCRIPTS_TO_RUN[@]}"; do
        script_path="${SCRIPTS_DIR}/${script}"

        # Check if the script exists
        if [ -f "$script_path" ]; then
            echo "Processing $script_path"

            # Change permission
            echo "Changing permission for $script_path"
            sudo chmod +x "$script_path"

            # Execute the script
            echo "Executing $script_path"
            if sudo "$script_path"; then
                echo "$script executed successfully."
            else
                echo "Error occurred while executing $script."
                exit 1
            fi
        else
            echo "Script $script_path does not exist."
        fi
    done

    echo "All specified scripts have been executed."

    # Add jammy-updates repository
    write_log "Ensuring jammy-updates repository is included"
    sudo add-apt-repository -y "deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse"
    write_log "jammy-updates repository added successfully"

    # Install Latest Updates
    write_log "Updating package lists"
    sudo DEBIAN_FRONTEND=noninteractive apt update -y
    sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y
    sudo DEBIAN_FRONTEND=noninteractive apt autoremove -y
    sudo DEBIAN_FRONTEND=noninteractive apt autoclean -y
    write_log "Package lists updated successfully"

    echo "Script completed successfully on $(date). The system will reboot in 5 seconds."
    sleep 5
    sudo reboot
} 2>&1 | tee -a "$LOG_FILE"
