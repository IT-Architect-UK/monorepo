#!/bin/sh

LOG_FILE="/logs/vmware-customisation-github-clone.log"

# Function to print to screen and append to log
log_and_print() {
    echo "$@" | tee -a "$LOG_FILE"
}

# Merge stderr into stdout for global error logging
exec 2>&1

log_and_print "----- Script started at $(date) -----"

# Get the absolute path of this script
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_NAME=$(basename "$0")
SCRIPT_PATH="$SCRIPT_DIR/$SCRIPT_NAME"

# Ensure the script is executable
chmod +x "$SCRIPT_PATH"

# Set up cron job to run this script on reboot if not already set
CRON_ENTRY="@reboot $SCRIPT_PATH"
if ! crontab -l 2>/dev/null | grep -Fq "$CRON_ENTRY"; then
    log_and_print "Setting up cron job for reboot"
    (crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -
else
    log_and_print "Cron job already set up"
fi

log_and_print "Setting Variables"
SOURCE_FILES_DIR="/source-files"
REPO_URL="https://github.com/IT-Architect-UK/monorepo.git"
REPO_NAME=$(basename -s .git "$REPO_URL")
TARGET_DIR="$SOURCE_FILES_DIR/github/$REPO_NAME"

log_and_print "Creating Directories"
mkdir -p /logs
mkdir -p "$SOURCE_FILES_DIR/github"
mkdir -p "$SOURCE_FILES_DIR/scripts"

# Update package lists (capture output)
log_and_print "Updating package lists..."
apt update | tee -a "$LOG_FILE"

# Install Git if not already installed
if ! command -v git > /dev/null 2>&1; then
    log_and_print "Installing Git"
    apt-get install git -y | tee -a "$LOG_FILE"
else
    log_and_print "Git already installed"
fi

log_and_print "Updating Monorepo"
mkdir -p "$TARGET_DIR"
if [ -d "$TARGET_DIR/.git" ]; then
    log_and_print "Repo exists, pulling latest changes"
    cd "$TARGET_DIR" || exit 1
    git pull | tee -a "$LOG_FILE"
else
    log_and_print "Cloning repo"
    git clone "$REPO_URL" "$TARGET_DIR" | tee -a "$LOG_FILE"
    cd "$TARGET_DIR" || exit 1
fi

# Make scripts executable (run after clone/pull to handle new files)
cd "$TARGET_DIR/scripts/bash/ubuntu/configuration" || exit 1
chmod +x *.sh
cd "$TARGET_DIR/scripts/bash/ubuntu/server-roles" || exit 1
chmod +x *.sh
cd "$TARGET_DIR/scripts/bash/ubuntu/packages" || exit 1
chmod +x *.sh
log_and_print "Made scripts executable"

log_and_print "Installing the latest updates ..."
apt-get upgrade -y | tee -a "$LOG_FILE"

# Conditional reboot if required (e.g., kernel update)
if [ -f /var/run/reboot-required ]; then
    log_and_print "Reboot required, rebooting system"
    reboot
else
    log_and_print "No reboot required"
fi

log_and_print "----- Script ended at $(date) -----"