#!/bin/bash

# Define log file name
LOG_FILE="/logs/apt-upgrade-$(date '+%Y%m%d').log"

# Create Logs Directory and Log File
mkdir -p /logs
touch $LOG_FILE

{
    echo "Script started on $(date)"

    # Verify sudo privileges without password
    if ! sudo -n true 2>/dev/null; then
        echo "Error: User does not have sudo privileges or requires a password for sudo."
        exit 1
    fi

    echo "Updating Package Lists"
    if sudo apt-get update; then
        echo "Successfully updated package lists."
    else
        echo "Error occurred while updating package lists."
        exit 1
    fi

    echo "Upgrading All Packages Without User Intervention"
    if sudo DEBIAN_FRONTEND=noninteractive apt-get -y upgrade; then
        echo "All packages have been successfully upgraded."
    else
        echo "Error occurred while upgrading packages."
        exit 1
    fi

    echo "Script completed successfully on $(date)"
} 2>&1 | tee -a $LOG_FILE
