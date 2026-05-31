#!/usr/bin/env bash
set -euo pipefail

# --- Helpers ---
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; exit 1; }

# Define the username
username="your_username"

# Create the user
sudo useradd -m $username

# Set the password for the user
sudo passwd $username

# Add the user to the sudo group
sudo usermod -aG sudo $username

# Create a log file
log_file="/var/log/user_creation.log"

# Log the user creation
echo "$(date): User $username created with sudo privileges" >> $log_file

# Print a success message
echo "User $username created successfully with sudo privileges"