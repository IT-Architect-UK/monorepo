#!/bin/bash

# Script to mount an NFS volume on Ubuntu with verbose logging

# Log file setup
LOG_FILE="/var/log/nfs_mount.log"
exec 1>>"$LOG_FILE" 2>&1
echo "===== NFS Mount Script Started: $(date) ====="

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
    log_message "ERROR: This script must be run as root"
    echo "Please run this script with sudo"
    exit 1
fi

# Check if NFS client is installed
if ! dpkg -l | grep -q nfs-common; then
    log_message "Installing nfs-common package"
    apt-get update && apt-get install -y nfs-common
    if [[ $? -ne 0 ]]; then
        log_message "ERROR: Failed to install nfs-common"
        exit 1
    fi
fi

# Prompt for NFS server hostname
echo "Enter the NFS server hostname or IP address"
echo "Example: nfs-server.example.com or 192.168.1.100"
read -p "NFS Server: " NFS_HOST
log_message "User entered NFS server: $NFS_HOST"

# Validate hostname/IP
if [[ -z "$NFS_HOST" ]]; then
    log_message "ERROR: No hostname/IP provided"
    echo "Hostname/IP cannot be empty"
    exit 1
fi

# Prompt for NFS export path
echo "Enter the NFS export path"
echo "Example: /export/data or /nfs/share"
read -p "NFS Path: " NFS_PATH
log_message "User entered NFS path: $NFS_PATH"

# Validate NFS path
if [[ -z "$NFS_PATH" || ! "$NFS_PATH" =~ ^/.* ]]; then
    log_message "ERROR: Invalid NFS path provided"
    echo "NFS path must start with '/' and cannot be empty"
    exit 1
fi

# Prompt for local mount point
echo "Enter the local mount point directory"
echo "Example: /mnt/nfs or /data"
read -p "Mount Point: " MOUNT_POINT
log_message "User entered mount point: $MOUNT_POINT"

# Validate and create mount point
if [[ -z "$MOUNT_POINT" || ! "$MOUNT_POINT" =~ ^/.* ]]; then
    log_message "ERROR: Invalid mount point provided"
    echo "Mount point must start with '/' and cannot be empty"
    exit 1
fi

if [[ ! -d "$MOUNT_POINT" ]]; then
    log_message "Creating mount point directory: $MOUNT_POINT"
    mkdir -p "$MOUNT_POINT"
    if [[ $? -ne 0 ]]; then
        log_message "ERROR: Failed to create mount point"
        echo "Failed to create mount point directory"
        exit 1
    fi
fi

# Test NFS server connectivity
log_message "Testing NFS server connectivity"
if ! ping -c 2 "$NFS_HOST" > /dev/null 2>&1; then
    log_message "WARNING: Unable to ping NFS server"
    echo "Warning: Could not ping NFS server. Continuing anyway..."
fi

# Attempt to mount NFS share
log_message "Attempting to mount $NFS_HOST:$NFS_PATH to $MOUNT_POINT"
mount -t nfs -o vers=4 "$NFS_HOST:$NFS_PATH" "$MOUNT_POINT"
if [[ $? -ne 0 ]]; then
    log_message "ERROR: Failed to mount NFS share"
    echo "Failed to mount NFS share. Check server configuration and try again."
    exit 1
fi

# Verify mount
if mount | grep -q "$MOUNT_POINT"; then
    log_message "SUCCESS: NFS share mounted successfully"
    echo "NFS share mounted successfully at $MOUNT_POINT"
else
    log_message "ERROR: Mount verification failed"
    echo "Mount verification failed"
    exit 1
fi

# Add to fstab for persistence
FSTAB_ENTRY="$NFS_HOST:$NFS_PATH $MOUNT_POINT nfs defaults,vers=4 0 0"
if ! grep -q "$NFS_HOST:$NFS_PATH" /etc/fstab; then
    log_message "Adding NFS mount to /etc/fstab"
    echo "$FSTAB_ENTRY" >> /etc/fstab
    if [[ $? -ne 0 ]]; then
        log_message "WARNING: Failed to update /etc/fstab"
        echo "Warning: Could not update /etc/fstab. Mount will not persist after reboot."
    else
        log_message "Successfully updated /etc/fstab"
        echo "Mount added to /etc/fstab for persistence"
    fi
fi

echo "===== NFS Mount Script Completed: $(date) ====="
log_message "Script execution completed"