#!/bin/bash

# Define log file name
LOG_FILE="/logs/dns-default-gateway-$(date '+%Y%m%d').log"

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

    # Get the host's primary IP address
    echo "Retrieving the host IP address..."
    host_ip=$(hostname -I | awk '{print $1}')
    if [ -z "$host_ip" ]; then
        echo "Failed to retrieve the host IP address."
        exit 1
    fi

    # Extract subnet from host IP and set new default gateway and nameserver IP
    echo "Setting new default gateway and nameserver IP..."
    subnet=$(echo $host_ip | cut -d '.' -f1-3)
    new_gateway_and_nameserver_ip="${subnet}.1"

    # Update resolv.conf: Remove all nameserver entries, then add the new gateway and nameserver IP
    echo "Updating /etc/resolv.conf..."
    {
        # Retain non-nameserver lines
        awk '!/nameserver/ {print}' /etc/resolv.conf;
        # Add the new gateway and nameserver IP as the nameserver
        echo "nameserver $new_gateway_and_nameserver_ip";
    } | sudo tee /etc/resolv.conf.tmp > /dev/null

    # Rename the temporary file to resolv.conf
    if sudo mv /etc/resolv.conf.tmp /etc/resolv.conf; then
        echo "DNS settings updated successfully."
    else
        echo "Failed to update DNS settings."
        exit 1
    fi

    echo "Done! DNS server set to match the default gateway."
    echo "Script completed successfully on $(date)"
} 2>&1 | tee -a $LOG_FILE
