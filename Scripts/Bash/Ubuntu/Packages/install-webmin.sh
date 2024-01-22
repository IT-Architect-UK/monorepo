#!/bin/sh

# Define log file name
LOG_FILE="/logs/install-webmin-$(date '+%Y%m%d').log"

# Create Logs Directory and Log File
mkdir -p /logs
touch $LOG_FILE

{
    echo "Script started on $(date)"

    # Verify sudo privileges
    if ! sudo -v; then
        echo "Error: This script requires sudo privileges."
        exit 1
    fi

    # Define source files directory
    SOURCE_FILES_DIR=/source-files

    echo "Updating Package Lists"
    if sudo apt-get update; then
        echo "Successfully updated package lists."
    else
        echo "Error occurred while updating package lists."
        exit 1
    fi

    # Install Webmin
    echo "Installing Webmin..."
    if wget -qO- http://www.webmin.com/jcameron-key.asc | sudo apt-key add - && \
       echo "deb http://download.webmin.com/download/repository sarge contrib" | sudo tee -a /etc/apt/sources.list.d/webmin.list && \
       sudo apt update && sudo apt install -y webmin; then
        echo "Successfully installed Webmin."
        sudo systemctl restart webmin
        if sudo systemctl status webmin | grep "active (running)"; then
            echo "Verification: Webmin is active and running."
        else
            echo "Verification failed: Webmin is not running."
            exit 1
        fi
    else
        echo "Error occurred while installing Webmin."
        exit 1
    fi

    echo "Script completed successfully on $(date)"
} 2>&1 | tee -a $LOG_FILE
