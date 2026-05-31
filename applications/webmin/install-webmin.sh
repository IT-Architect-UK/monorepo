#!/usr/bin/env bash
set -euo pipefail

# --- Helpers ---
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; exit 1; }

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
    # Clean up any existing Webmin repository and key (from prior failed installs)
    echo "Cleaning up existing Webmin repository and key..."
    sudo rm -f /etc/apt/sources.list.d/webmin.list
    sudo rm -f /usr/share/keyrings/webmin-archive-keyring.gpg
    echo "Cleanup completed."
    # Download and run official Webmin setup script (non-interactively)
    echo "Downloading and running official Webmin setup script..."
    if curl -o webmin-setup-repo.sh https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh && echo y | sudo sh webmin-setup-repo.sh; then
        echo "Webmin repository and GPG key configured successfully."
        rm -f webmin-setup-repo.sh  # Clean up the downloaded script
    else
        echo "Error occurred while setting up Webmin repository."
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
    if sudo apt-get install -y webmin --install-recommends; then
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