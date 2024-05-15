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

    # Update package lists
    echo "Updating Package Lists"
    if sudo apt-get update; then
        echo "Successfully updated package lists."
    else
        echo "Error occurred while updating package lists."
        exit 1
    fi

    # Define Webmin key URL and Webmin source list
    WEBMIN_KEY_URL=http://www.webmin.com/jcameron-key.asc
    WEBMIN_SOURCE_LIST="/etc/apt/sources.list.d/webmin.list"
    WEBMIN_KEYRING="/usr/share/keyrings/webmin-archive-keyring.gpg"

    # Download and install Webmin GPG key
    echo "Downloading and installing Webmin GPG key..."
    if wget -qO- "$WEBMIN_KEY_URL" | gpg --dearmor | sudo tee "$WEBMIN_KEYRING" >/dev/null; then
        echo "Webmin GPG key installed successfully."
    else
        echo "Error occurred while installing Webmin GPG key."
        exit 1
    fi

    # Add Webmin repository with signed-by option
    echo "Adding Webmin repository..."
    if echo "deb [signed-by=$WEBMIN_KEYRING] http://download.webmin.com/download/repository sarge contrib" | sudo tee "$WEBMIN_SOURCE_LIST" >/dev/null; then
        echo "Webmin repository added successfully."
    else
        echo "Error occurred while adding Webmin repository."
        exit 1
    fi

    # Update package lists after adding new repository
    echo "Updating Package Lists after adding Webmin repository"
    if sudo apt-get update; then
        echo "Successfully updated package lists."
    else
        echo "Error occurred while updating package lists."
        exit 1
    fi

    # Install Webmin
    echo "Installing Webmin..."
    if sudo apt-get install -y webmin; then
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
