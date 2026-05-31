#!/bin/bash

# Define log file name
LOG_FILE="/logs/setup-iptables-$(date '+%Y%m%d').log"

# Create Logs Directory and Log File
mkdir -p /logs
touch "$LOG_FILE"

{
    echo "Script started on $(date)"

    # Verify sudo privileges without password
    if ! sudo -n true 2>/dev/null; then
        echo "Error: User does not have sudo privileges or requires a password for sudo."
        exit 1
    fi

    # Array of private subnets
    subnets=("10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16")

    echo "Configuring Firewall Rules"

    # Flush existing rules and set chain policies to DROP
    echo "Flushing existing rules..."
    sudo iptables -F
    sudo iptables -X
    sudo iptables -t nat -F
    sudo iptables -t nat -X
    sudo iptables -t mangle -F
    sudo iptables -t mangle -X
    sudo iptables -P INPUT DROP
    sudo iptables -P FORWARD DROP
    sudo iptables -P OUTPUT DROP

    echo "Setting up basic rules..."
    # Allow all outbound traffic
    sudo iptables -A OUTPUT -j ACCEPT
    # Allow established and related incoming connections
    sudo iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    # Allow essential traffic
    sudo iptables -A INPUT -i lo -j ACCEPT
    sudo iptables -A OUTPUT -o lo -j ACCEPT
    for subnet in "${subnets[@]}"; do
        sudo iptables -A INPUT -s "$subnet" -j ACCEPT
    done

    # Allow SSH to maintain connectivity
    echo "Adding rule to allow SSH..."
    SSH_PORT=$(grep ^Port /etc/ssh/sshd_config | cut -d ' ' -f2)
    if [ -z "$SSH_PORT" ]; then
        SSH_PORT=22 # Default SSH port
    fi
    sudo iptables -A INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT

    # Allow specific TCP ports from any source
    echo "Adding rules for TCP ports 8545, 8546, and 7000..."
    sudo iptables -A INPUT -p tcp --dport 8545 -s 0.0.0.0/0 -j ACCEPT
    sudo iptables -A INPUT -p tcp --dport 8546 -s 0.0.0.0/0 -j ACCEPT
    sudo iptables -A INPUT -p tcp --dport 7400 -s 0.0.0.0/0 -j ACCEPT
    sudo iptables -A INPUT -p udp --dport 7400 -s 0.0.0.0/0 -j ACCEPT

    # Allow ICMP (Ping) from private subnets
    echo "Allowing ICMP from private subnets..."
    for subnet in "${subnets[@]}"; do
        sudo iptables -A INPUT -s "$subnet" -p icmp -j ACCEPT
    done

    # Install iptables-persistent
    echo "Installing iptables-persistent..."
    if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent; then
        echo "iptables-persistent installed successfully."
    else
        echo "Error occurred while installing iptables-persistent."
        exit 1
    fi

    # Save the rules
    echo "Saving IPTables rules..."
    if sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null; then
        echo "IPTables rules saved successfully."
    else
        echo "Error occurred while saving IPTables rules."
        exit 1
    fi

    echo "Firewall rules configured and saved."
    echo "Script completed successfully on $(date)"
} 2>&1 | tee -a "$LOG_FILE"