#!/bin/sh

if [ x$1 = x"precustomization" ]; then
    echo "Do Precustomization tasks"

elif [ x$1 = x"postcustomization" ]; then
    echo "Do Postcustomization tasks"

# Define Variables
LOG_FILE="/logs/vmware-customisation-github-clone.log"
SOURCE_FILES_DIR=/source-files

# Creating logs & source-files directories
mkdir -p /logs /source-files/scripts

# Function to write log with timestamp
write_log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

write_log "Updating Package Lists"
apt update

# Disable Cloud-Init's network configuration capabilities
write_log "Starting Cloud-Init disable process"
write_log "Disabling Cloud-Init network configuration"
echo "network: {config: disabled}" > /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg

write_log "Disabling Cloud-Init"
touch /etc/cloud/cloud-init.disabled
write_log "Cloud-Init disabled successfully"

write_log "Checking if Git is installed..."
if ! command -v git >/dev/null 2>&1; then
    write_log "Git could not be found, installing now..."
    apt-get install git -y
    write_log "Git has been installed."
else
    write_log "Git is already installed."
fi

write_log "Cloning GitHub Repository"
REPO_URL="https://github.com/IT-Architect-UK/Monorepo.git"
REPO_NAME=$(basename -s .git "$REPO_URL")
TARGET_DIR=$SOURCE_FILES_DIR/github/$REPO_NAME

if [ -d "$TARGET_DIR" ]; then
    write_log "Target directory already exists, updating repository..."
    (cd $TARGET_DIR && git pull)
else
    write_log "Creating target directory and cloning repository..."
    mkdir -p $TARGET_DIR
    git clone $REPO_URL $TARGET_DIR
fi
write_log "Repository operation completed."

apt upgrade -y
apt autoclean -y
write_log "System updated and cleaned."

write_log "Script completed."
reboot

fi
