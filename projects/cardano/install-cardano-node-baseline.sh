#!/bin/bash

: '
.SYNOPSIS
This script executes a series of scripts for server baseline configuration.

.DESCRIPTION
The script performs the following actions:
- Ensures the log directory exists and creates a log file.
- Disables Cloud-Init.
- Verifies if the user has sudo privileges without requiring a password.
- Executes a predefined list of scripts for server configuration, logging the output.
- Performs a full system upgrade, removes unnecessary packages, and reboots.

.NOTES
Version:            1.1
Author:             Darren Pilkington
Modification Date:  06-04-2025
'

# Configuration
SCRIPTS_DIR="/source-files/github/monorepo/scripts/bash/ubuntu"
PROJECTS_DIR="/source-files/github/monorepo/projects/cardano"
LOG_DIR="/logs"
LOG_FILE="$LOG_DIR/server-baseline-$(date '+%Y%m%d').log"
MIN_DISK_SPACE_MB=1024  # Minimum required disk space in MB
REBOOT=true  # Default reboot behavior

# Cleanup function for unexpected exits
cleanup() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Script interrupted - cleaning up" >&2
    exit 1
}

# Set trap for script interruption
trap cleanup INT TERM

# Function to write log with timestamp
write_log() {
    local message="$1"
    # Try to write without sudo, if fails use sudo, if that fails use stderr
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE" 2>/dev/null || \
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | sudo tee -a "$LOG_FILE" >/dev/null || \
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >&2
}

# Check Ubuntu version
check_ubuntu_version() {
    if ! lsb_release -d | grep -qi "ubuntu"; then
        write_log "Error: This script is designed for Ubuntu systems only"
        exit 1
    fi
}

# Check available disk space
check_disk_space() {
    local available_space=$(df -m / | tail -1 | awk '{print $4}')
    if [ "$available_space" -lt "$MIN_DISK_SPACE_MB" ]; then
        write_log "Error: Insufficient disk space. Required: ${MIN_DISK_SPACE_MB}MB, Available: ${available_space}MB"
        exit 1
    fi
}

# Create log directory and file
setup_logging() {
    # Try creating directory as user first, then with sudo if needed
    mkdir -p "$LOG_DIR" 2>/dev/null || sudo mkdir -p "$LOG_DIR" || {
        echo "Error: Cannot create log directory $LOG_DIR" >&2
        exit 1
    }

    # Set directory permissions
    sudo chown "$USER:$(id -gn)" "$LOG_DIR" 2>/dev/null
    sudo chmod 775 "$LOG_DIR" 2>/dev/null

    # Create log file
    touch "$LOG_FILE" 2>/dev/null || sudo touch "$LOG_FILE" || {
        echo "Error: Cannot create log file $LOG_FILE" >&2
        exit 1
    }

Parece que hubo un corte en el mensaje anterior. Aquí está la continuación del script completo:

```bash
    # Set file permissions
    sudo chown "$USER:$(id -gn)" "$LOG_FILE" 2>/dev/null
    sudo chmod 664 "$LOG_FILE" 2>/dev/null
}

# Main execution
setup_logging
write_log "Script started"

# Preliminary checks
check_ubuntu_version
if ! sudo -n true 2>/dev/null; then
    write_log "Error: User requires password for sudo"
    exit 1
fi
check_disk_space

# Disable Cloud-Init (requires sudo)
write_log "Disabling Cloud-Init"
sudo touch /etc/cloud/cloud-init.disabled || {
    write_log "Failed to disable Cloud-Init"
    exit 1
}
write_log "Cloud-Init disabled successfully"

# List of configuration scripts
SCRIPTS_TO_RUN=(
    "packages/install-webmin.sh"
    "configuration/extend-disks.sh"
    "configuration/disable-ipv6.sh"
    "configuration/dns-default-gateway.sh"
    "configuration/setup-iptables.sh"
    "packages/install-docker-and-docker-compose.sh"
    "packages/install-portainer-agent.sh"
    "configuration/disable-cloud-init.sh"
)

# Execute configuration scripts
for script in "${SCRIPTS_TO_RUN[@]}"; do
    script_path="${SCRIPTS_DIR}/${script}"
    if [ -f "$script_path" ]; then
        write_log "Processing $script_path"
        chmod +x "$script_path" 2>/dev/null || sudo chmod +x "$script_path"
        if sudo "$script_path"; then
            write_log "$script executed successfully"
        else
            write_log "Error executing $script - Exit code: $?"
            exit 1
        fi
    else
        write_log "Script $script_path not found"
    fi
done

# Add current user to docker group (requires sudo)
CURRENT_USER=$(logname)
echo "Adding user $CURRENT_USER to docker group..."
sudo usermod -aG docker "$CURRENT_USER"

# Install Cardano Guild Prereqs
if [ -f "$PROJECTS_DIR/guild-deploy-prereqs.sh" ]; then
    write_log "Installing Cardano Guild Prerequisites"
    chmod +x "$PROJECTS_DIR/guild-deploy-prereqs.sh" 2>/dev/null || sudo chmod +x "$PROJECTS_DIR/guild-deploy-prereqs.sh"
    if sudo "$PROJECTS_DIR/guild-deploy-prereqs.sh"; then
        write_log "Cardano Guild Prerequisites installed successfully"
    else
        write_log "Error installing Cardano Guild Prerequisites - Exit code: $?"
        exit 1
    fi
else
    write_log "Warning: Cardano Guild Prerequisites script not found"
fi

# Configure Cardano IPTABLES
if [ -d "$PROJECTS_DIR" ]; then
    cd "$PROJECTS_DIR"
    if [ -f "configure-cardano-node-iptables.sh" ]; then
        write_log "Configuring cardano IPTABLES"
        chmod +x ./configure-cardano-node-iptables.sh 2>/dev/null || sudo chmod +x ./configure-cardano-node-iptables.sh
        if sudo ./configure-cardano-node-iptables.sh; then
            write_log "cardano IPTABLES configured successfully"
        else
            write_log "cardano IPTABLES configuration failed - Exit code: $?"
            exit 1
        fi
    else
        write_log "Warning: cardano IPTABLES script not found"
    fi
else
    write_log "Warning: PROJECTS_DIR not found"
fi

# System updates (requires sudo)
write_log "Performing system updates"
if ! sudo add-apt-repository -y "deb http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse"; then
    write_log "Failed to add jammy-updates repository"
    exit 1
fi

if ! sudo DEBIAN_FRONTEND=noninteractive apt update -y || \
   ! sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y || \
   ! sudo DEBIAN_FRONTEND=noninteractive apt autoremove -y || \
   ! sudo DEBIAN_FRONTEND=noninteractive apt autoclean -y; then
    write_log "System update failed"
    exit 1
fi
write_log "System updates completed successfully"

# Completion and reboot
write_log "Script completed successfully"
if [ "$REBOOT" = true ]; then
    write_log "System will reboot in 5 seconds"
    sleep 5
    sudo reboot
else
    write_log "Reboot skipped (REBOOT=false)"
fi

exit 0