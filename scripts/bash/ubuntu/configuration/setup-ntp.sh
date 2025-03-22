#!/bin/bash

: '
.SYNOPSIS
This script configures systemd-timesyncd to use the default gateway as the NTP server.

.DESCRIPTION
The script performs the following actions:
- Detects the default gateway IP.
- Backs up the existing timesyncd.conf file.
- Updates /etc/systemd/timesyncd.conf to use the default gateway as the NTP server.
- Restarts the systemd-timesyncd service.
- Verifies NTP synchronization status.

.NOTES
Version:            1.0
Author:             Darren Pilkington
Creation Date:      22-03-2025
'

# Configuration
LOG_DIR="/logs"
LOG_FILE="$LOG_DIR/server-baseline-$(date '+%Y%m%d').log"

# Function to write log with timestamp
# If called from another script, this can be overridden; otherwise, it works standalone
write_log() {
    local message="$1"
    # Check if LOG_FILE is set and writable, else fallback to stderr
    if [ -n "$LOG_FILE" ] && [ -w "$(dirname "$LOG_FILE")" ]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" >&2
    fi
}

# Ensure log directory exists (standalone mode)
if [ ! -d "$LOG_DIR" ]; then
    mkdir -p "$LOG_DIR" || {
        echo "Error: Cannot create log directory $LOG_DIR" >&2
        exit 1
    }
    touch "$LOG_FILE" || {
        echo "Error: Cannot create log file $LOG_FILE" >&2
        exit 1
    }
    chmod 664 "$LOG_FILE" 2>/dev/null
fi

# Main execution
write_log "Configuring NTP to use default gateway"

# Get the default gateway
DEFAULT_GATEWAY=$(ip route | grep default | awk '{print $3}')
if [ -z "$DEFAULT_GATEWAY" ]; then
    write_log "Error: Could not determine default gateway"
    exit 1
fi

# Backup original timesyncd.conf
sudo cp /etc/systemd/timesyncd.conf /etc/systemd/timesyncd.conf.bak || {
    write_log "Failed to backup timesyncd.conf"
    exit 1
}
write_log "Backed up timesyncd.conf to timesyncd.conf.bak"

# Update timesyncd.conf with the default gateway as NTP server
# Handle both commented #NTP= and existing NTP= lines
if grep -q "^#NTP=" /etc/systemd/timesyncd.conf; then
    sudo sed -i "s/#NTP=.*/NTP=$DEFAULT_GATEWAY/" /etc/systemd/timesyncd.conf || {
        write_log "Failed to update timesyncd.conf"
        exit 1
    }
elif grep -q "^NTP=" /etc/systemd/timesyncd.conf; then
    sudo sed -i "s/^NTP=.*/NTP=$DEFAULT_GATEWAY/" /etc/systemd/timesyncd.conf || {
        write_log "Failed to update timesyncd.conf"
        exit 1
    }
else
    # If no NTP line exists, append it
    echo "NTP=$DEFAULT_GATEWAY" | sudo tee -a /etc/systemd/timesyncd.conf || {
        write_log "Failed to append NTP setting to timesyncd.conf"
        exit 1
    }
fi
write_log "Updated timesyncd.conf with NTP server: $DEFAULT_GATEWAY"

# Restart systemd-timesyncd to apply changes
if ! sudo systemctl restart systemd-timesyncd; then
    write_log "Failed to restart systemd-timesyncd"
    exit 1
fi
write_log "systemd-timesyncd restarted successfully"

# Verify NTP sync (optional, for logging)
if timedatectl | grep -q "System clock synchronized: yes"; then
    write_log "NTP synchronization confirmed"
else
    write_log "Warning: NTP synchronization not yet active (may take a moment)"
fi

write_log "NTP configuration completed successfully"
exit 0