#!/bin/sh

# Define Variables
LOG_FILE="/logs/vmware-customisation-github-clone.log"
SOURCE_FILES_DIR="/source-files"
REPO_URL="https://github.com/IT-Architect-UK/Monorepo.git"
REPO_NAME=$(basename -s .git "$REPO_URL")

# Creating logs & source-files directories
mkdir -p /logs /source-files/scripts

# Function to write log with timestamp
write_log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

if [ x"$1" = x"precustomization" ]; then
    write_log "Do Precustomization tasks"

elif [ x"$1" = x"postcustomization" ]; then
    write_log "Do Postcustomization tasks"

    write_log "Updating Package Lists"
    apt update

    write_log "Checking if Git is installed..."
    if ! command -v git >/dev/null 2>&1; then
        write_log "Git could not be found, installing now..."
        apt-get install git -y
        write_log "Git has been installed."
    else
        write_log "Git is already installed."
    fi

    write_log "Cloning GitHub Repository"
    TARGET_DIR="$SOURCE_FILES_DIR/github/$REPO_NAME"
    if [ -d "$TARGET_DIR" ]; then
        write_log "Target directory already exists, updating repository..."
        (cd "$TARGET_DIR" && git pull) || write_log "Failed to pull the repository"
    else
        write_log "Creating target directory..."
        mkdir -p "$TARGET_DIR" || write_log "Failed to create target directory"
        write_log "Cloning repository..."
        git clone "$REPO_URL" "$TARGET_DIR" || write_log "Failed to clone the repository"
    fi
    write_log "Repository operation completed."

    apt upgrade -y
    apt autoclean -y
    write_log "System updated and cleaned."

    # Disable Cloud-Init's network configuration capabilities
    write_log "Starting Cloud-Init disable process"
    write_log "Disabling Cloud-Init network configuration"
    echo "network: {config: disabled}" > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
    write_log "Disabling Cloud-Init"
    touch /etc/cloud/cloud-init.disabled
    write_log "Cloud-Init disabled successfully"

    write_log "Script completed."

    reboot
fi
