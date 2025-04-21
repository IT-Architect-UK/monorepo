#!/bin/bash

# Script to mount an NFS volume on Ubuntu with verbose logging
#
# Purpose:
#   This script automates the process of mounting an NFS (Network File System) share
#   on an Ubuntu system. It checks for required dependencies, validates user-provided
#   or hardcoded NFS server details, creates a local mount point, mounts the NFS share,
#   and optionally adds the mount to /etc/fstab for persistence across reboots.
#
# Usage:
#   1. Update the hardcoded NFS_HOST, NFS_PATH, and MOUNT_POINT variables below to
#      match your NFS server configuration.
#   2. Run the script with root privileges: `sudo ./nfs_mount.sh`
#   3. Check the log file (/var/log/nfs_mount.log) and terminal output for status
#      messages and errors.
#
# Requirements:
#   - Ubuntu system with internet access (for installing nfs-common if needed).
#   - Root or sudo privileges.
#   - NFS server with a valid export path accessible from this client.
#   - Network connectivity to the NFS server.
#
# Logging:
#   - All actions and errors are logged to /var/log/nfs_mount.log.
#   - Messages are also displayed on the terminal for immediate feedback.
#
# Notes:
#   - Ensure the NFS server is configured to allow mounts from this client (check
#     /etc/exports on the server).
#   - The script uses NFS version 4 by default (vers=4).
#   - Modify hardcoded values as needed or revert to interactive prompts if desired.

# Log file setup
LOG_FILE="/var/log/nfs_mount.log"
echo "===== NFS Mount Script Started: $(date) =====" | tee -a "$LOG_FILE"

# Function to log messages to both log file and terminal
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE" > /dev/tty
}

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
    log_message "ERROR: This script must be run as root"
    echo "Please run this script with sudo" > /dev/tty
    exit 1
fi

# Check if NFS client is installed
if ! dpkg -l | grep -q nfs-common; then
    log_message "Installing nfs-common package"
    apt-get update && apt-get install -y nfs-common
    if [[ $? -ne 0 ]]; then
        log_message "ERROR: Failed to install nfs-common"
        echo "Failed to install nfs-common" > /dev/tty
        exit 1
    fi
fi

# Define NFS server details (replace with your values)
NFS_HOST="192.168.1.100"  # Replace with your NFS server IP/hostname
log_message "Using NFS server: $NFS_HOST"

# Validate hostname/IP
if [[ -z "$NFS_HOST" ]]; then
    log_message "ERROR: No hostname/IP provided"
    echo "Hostname/IP cannot be empty" > /dev/tty
    exit 1
fi

# Define NFS export path
NFS_PATH="/export/data"  # Replace with your NFS export path
log_message "Using NFS path: $NFS_PATH"

# Validate NFS path
if [[ -z "$NFS_PATH" || ! "$NFS_PATH" =~ ^/.* ]]; then
    log_message "ERROR: Invalid NFS path provided"
    echo "NFS path must start with '/' and cannot be empty" > /dev/tty
    exit 1
fi

# Define local mount point
MOUNT_POINT="/mnt/nfs"  # Replace with your mount point
log_message "Using mount point: $MOUNT_POINT"

# Validate and create mount point
if [[ -z "$MOUNT_POINT" || ! "$MOUNT_POINT" =~ ^/.* ]]; then
    log_message "ERROR: Invalid mount point provided"
    echo "Mount point must start with '/' and cannot be empty" > /dev/tty
    exit 1
fi

if [[ ! -d "$MOUNT_POINT" ]]; then
    log_message "Creating mount point directory: $MOUNT_POINT"
    mkdir -p "$MOUNT_POINT"
    if [[ $? -ne 0 ]]; then
        log_message "ERROR: Failed to create mount point"
        echo "Failed to create mount point directory" > /dev/tty
        exit 1
    fi
fi

# Test NFS server connectivity
log_message "Testing NFS server connectivity"
if ! ping -c 2 "$NFS_HOST" > /dev/null 2>&1; then
    log_message "WARNING: Unable to ping NFS server"
    echo "Warning: Could not ping NFS server. Continuing anyway..." > /dev/tty
fi

# Attempt to mount NFS share
log_message "Attempting to mount $NFS_HOST:$NFS_PATH to $MOUNT_POINT"
mount -t nfs -o vers=4 "$NFS_HOST:$NFS_PATH" "$MOUNT_POINT"
if [[ $? -ne 0 ]]; then
    log_message "ERROR: Failed to mount NFS share"
    echo "Failed to mount NFS share. Check server configuration and try again." > /dev/tty
    exit 1
fi

# Verify mount
if mount | grep -q "$MOUNT_POINT"; then
    log_message "SUCCESS: NFS share mounted successfully"
    echo "NFS share mounted successfully at $MOUNT_POINT" > /dev/tty
else
    log_message "ERROR: Mount verification failed"
    echo "Mount verification failed" > /dev/tty
    exit 1
fi

# Add to fstab for persistence
FSTAB_ENTRY="$NFS_HOST:$NFS_PATH $MOUNT_POINT nfs defaults,vers=4 0 0"
if ! grep -q "$NFS_HOST:$NFS_PATH" /etc/fstab; then
    log_message "Adding NFS mount to /etc/fstab"
    echo "$FSTAB_ENTRY" >> /etc/fstab
    if [[ $? -ne 0 ]]; then
        log_message "WARNING: Failed to update /etc/fstab"
        echo "Warning: Could not update /etc/fstab. Mount will not persist after reboot." > /dev/tty
    else
        log_message "Successfully updated /etc/fstab"
        echo "Mount added to /etc/fstab for persistence" > /dev/tty
    fi
fi

echo "===== NFS Mount Script Completed: $(date) =====" | tee -a "$LOG_FILE"
log_message "Script execution completed"