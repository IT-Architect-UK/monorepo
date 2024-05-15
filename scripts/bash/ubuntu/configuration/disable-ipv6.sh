#!/bin/sh

# Define log file name
LOG_FILE="/logs/disable-ipv6-$(date '+%Y%m%d').log"

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

    echo "Disabling IPv6"

    # Append IPv6 disable settings to sysctl.conf
    if echo "net.ipv6.conf.all.disable_ipv6=1" | sudo tee -a /etc/sysctl.conf && \
       echo "net.ipv6.conf.default.disable_ipv6=1" | sudo tee -a /etc/sysctl.conf && \
       echo "net.ipv6.conf.lo.disable_ipv6=1" | sudo tee -a /etc/sysctl.conf; then
        echo "IPv6 disable settings added to sysctl.conf."
    else
        echo "Error occurred while updating sysctl.conf."
        exit 1
    fi

    # Reload sysctl configuration
    if sudo sysctl -p; then
        echo "Sysctl configuration reloaded successfully."
    else
        echo "Error occurred while reloading sysctl configuration."
        exit 1
    fi

    echo "IPv6 has been successfully disabled."
    echo "Script completed successfully on $(date)"
} 2>&1 | tee -a $LOG_FILE
