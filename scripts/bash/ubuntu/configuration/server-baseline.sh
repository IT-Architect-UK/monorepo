#!/bin/bash

: '
.SYNOPSIS
This script executes a series of scripts for server baseline configuration.

.DESCRIPTION
The script performs the following actions:
- Ensures the log directory exists and creates a log file.
- Disables Cloud-Init.
- Verifies if the user has sudo privileges without requiring a password.
- Executes a predefined list of scripts for server configuration, logging the output.

.NOTES
Version:            1.0
Author:             Your Name
Modification Date:  08-03-2024
'

# Define the scripts directory
SCRIPTS_DIR="/source-files/github/monorepo/scripts/bash/ubuntu"

# Define log file name and directory
LOG_DIR="/logs"
LOG_FILE="$LOG_DIR/server-baseline-$(date '+%Y%m%d').log"

# Create Logs Directory and Log File
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

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
        "packages/install-webmin.sh"
        "configuration/extend-disks.sh"
        "configuration/disable-ipv6.sh"
        "configuration/dns-default-gateway.sh"
        "configuration/setup-iptables.sh"
        "configuration/disable-cloud-init.sh"
        "configuration/apt-get-upgrade.sh"
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
    echo "Script completed successfully on $(date). Reboot if necessary."
} 2>&1 | tee -a "$LOG_FILE"
