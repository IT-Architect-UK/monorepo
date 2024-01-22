#!/bin/sh

# Define log file name
LOG_FILE="/logs/ntp-chrony-config-$(date '+%Y%m%d').log"

# Create Logs Directory and Log File
mkdir -p /logs
touch $LOG_FILE

{
    echo "Script started on $(date)"

    # Verify sudo privileges without password
    if ! sudo -n true 2>/dev/null; then
        echo "Error: User does not have sudo privileges or requires a password for sudo."
        exit 1
    fi

    echo "Configuring NTP"

    # Install chrony
    echo "Installing chrony..."
    if sudo apt-get install chrony -y; then
        echo "Chrony installed successfully."
    else
        echo "Error occurred while installing chrony."
        exit 1
    fi

    # Configure chrony
    echo "Configuring chrony..."
    if echo "pool pool.ntp.org iburst minpoll 1 maxpoll 2 maxsources 3
keyfile /etc/chrony/chrony.keys
driftfile /var/lib/chrony/chrony.drift
logdir /var/log/chrony
maxupdateskew 5.0
rtcsync
makestep 0.1 -1" | sudo tee /etc/chrony/chrony.conf > /dev/null; then
        echo "Chrony configuration updated."
    else
        echo "Error occurred while configuring chrony."
        exit 1
    fi

    # Restart the chrony service
    echo "Restarting the chrony service..."
    if sudo systemctl restart --no-ask-password chrony.service; then
        echo "Chrony service restarted successfully."
        sudo chronyc sources
    else
        echo "Error occurred while restarting the chrony service."
        exit 1
    fi

    echo "NTP configuration completed."
    echo "Script completed successfully on $(date)"
} 2>&1 | tee -a $LOG_FILE
