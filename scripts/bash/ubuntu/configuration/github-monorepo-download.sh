#!/bin/sh

# Redirect all output to log file (append mode)
LOG_FILE="/logs/vmware-customisation-github-clone.log"
exec >> "$LOG_FILE" 2>&1

echo "----- Script started at $(date) -----"

echo "Setting Variables"
SOURCE_FILES_DIR="/source-files"
REPO_URL="https://github.com/IT-Architect-UK/monorepo.git"
REPO_NAME=$(basename -s .git "$REPO_URL")
TARGET_DIR="$SOURCE_FILES_DIR/github/$REPO_NAME"

echo "Creating Directories"
mkdir -p /logs
mkdir -p "$SOURCE_FILES_DIR/github"
mkdir -p "$SOURCE_FILES_DIR/scripts"

# Update package lists
apt update

# Install Git if not already installed
if ! command -v git > /dev/null 2>&1; then
    echo "Installing Git"
    apt-get install git -y
else
    echo "Git already installed"
fi

echo "Updating Monorepo"
mkdir -p "$TARGET_DIR"
if [ -d "$TARGET_DIR/.git" ]; then
    echo "Repo exists, pulling latest changes"
    cd "$TARGET_DIR" || exit 1
    git pull
else
    echo "Cloning repo"
    git clone "$REPO_URL" "$TARGET_DIR"
    cd "$TARGET_DIR" || exit 1
fi

# Make scripts executable (run after clone/pull to handle new files)
cd "$TARGET_DIR/scripts/bash/ubuntu/configuration" || exit 1
chmod +x *.sh
cd "$TARGET_DIR/scripts/bash/ubuntu/server-roles" || exit 1
chmod +x *.sh
cd "$TARGET_DIR/scripts/bash/ubuntu/packages" || exit 1
chmod +x *.sh

echo "Installing the latest updates ..."
apt-get upgrade -y

# Conditional reboot if required (e.g., kernel update)
if [ -f /var/run/reboot-required ]; then
    echo "Reboot required, rebooting system"
    reboot
else
    echo "No reboot required"
fi

echo "----- Script ended at $(date) -----"