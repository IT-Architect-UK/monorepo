#!/bin/bash

# Introduction (within script comments):
# This script configures a Docker Swarm cluster on Ubuntu servers. It supports both manager and worker nodes,
# prompting for the number of hosts, node role, host FQDNs, and private subnet. It sets up IPTABLES firewall rules
# to secure Swarm communication and logs all actions to /logs/setup-docker-swarm-YYYYMMDD.log.
# Prerequisites: Docker installed, sudo privileges, DNS-resolvable FQDNs for all nodes.
# Note on node availability: The manager node must be online when workers join, but not all nodes need to be online
# when initializing the manager or joining as workers. Offline nodes can join later using the same join token.
# Firewall note: Uses a dedicated DOCKER-SWARM chain to preserve existing iptables rules, ensuring SSH connectivity is not disrupted.

# Define log file name
# Note: The log file is timestamped to avoid overwrites and stored in /logs for centralized logging.
LOG_FILE="/logs/setup-docker-swarm-$(date '+%Y%m%d').log"

# Create Logs Directory and Log File
# Note: Ensures the /logs directory exists and creates the log file if it doesn't. This allows tracking of all script actions.
mkdir -p /logs
touch $LOG_FILE

{
    echo "Script started on $(date)" | tee -a $LOG_FILE

    # Verify sudo privileges
    # Note: Checks if the user has sudo access, as many operations (e.g., iptables, Docker commands) require elevated privileges.
    if ! sudo -v; then
        echo "Error: This script requires sudo privileges." | tee -a $LOG_FILE
        exit 1
    fi

    # Verify Docker is installed
    # Note: Ensures Docker is installed and available, as the script depends on Docker commands for Swarm setup.
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed. Please install Docker first." | tee -a $LOG_FILE
        exit 1
    fi

    # Prompt for cluster configuration
    # Note: Collects the total number of hosts in the cluster to validate the number of FQDNs provided later.
    echo "Enter the number of hosts in the Docker Swarm cluster:"
    read NUM_HOSTS
    if ! [[ "$NUM_HOSTS" =~ ^[0-9]+$ ]] || [ "$NUM_HOSTS" -lt 1 ]; then
        echo "Error: Invalid number of hosts." | tee -a $LOG_FILE
        exit 1
    fi

    # Note: Prompts for the role of the current node (manager or worker) to determine the Swarm setup logic.
    echo "Enter the role of this node (manager/worker):"
    read NODE_ROLE
    if [[ "$NODE_ROLE" != "manager" && "$NODE_ROLE" != "worker" ]]; then
        echo "Error: Role must be 'manager' or 'worker'." | tee -a $LOG_FILE
        exit 1
    fi

    # Collect hostnames
    # Note: Gathers FQDNs for all nodes to ensure proper identification and communication.
    # Validates DNS resolution for each FQDN to catch potential network issues early.
    HOSTS=()
    echo "Enter the FQDNs of all hosts in the cluster (one per line, $NUM_HOSTS total):"
    for ((i=1; i<=NUM_HOSTS; i++)); do
        read HOST
        HOSTS+=("$HOST")
        if ! ping -c 1 "$HOST" &> /dev/null; then
            echo "Warning: Could not resolve $HOST via DNS." | tee -a $LOG_FILE
        fi
    done

    # Prompt for private subnet for Docker Swarm
    # Note: Requests a private subnet (e.g., 10.20.0.0/16) for Docker Swarm’s overlay network to avoid IP conflicts.
    echo "Enter the private subnet for Docker Swarm (e.g., 10.20.0.0/16):"
    read DOCKER_SUBNET
    if ! [[ "$DOCKER_SUBNET" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "Error: Invalid subnet format." | tee -a $LOG_FILE
        exit 1
    fi

    # Get this node's FQDN
    # Note: Retrieves the current node’s FQDN to identify it within the cluster and for manager IP resolution.
    THIS_HOST=$(hostname -f)
    echo "This node's FQDN is $THIS_HOST" | tee -a $LOG_FILE

    # Configure IPTABLES firewall rules
    # Note: Creates a new chain for Docker Swarm rules to avoid modifying existing rules.
    # This ensures existing SSH rules are preserved while adding necessary Swarm ports.
    echo "Configuring IPTABLES firewall rules for Docker Swarm" | tee -a $LOG_FILE

    # Create a new chain for Docker Swarm rules
    sudo iptables -N DOCKER-SWARM 2>/dev/null || true
    # Flush only the DOCKER-SWARM chain to avoid affecting other rules
    sudo iptables -F DOCKER-SWARM
    # Add the DOCKER-SWARM chain to INPUT if not already present
    sudo iptables -C INPUT -j DOCKER-SWARM 2>/dev/null || sudo iptables -A INPUT -j DOCKER-SWARM

    # Add rules to the DOCKER-SWARM chain
    sudo iptables -A DOCKER-SWARM -m state --state ESTABLISHED,RELATED -j ACCEPT
    sudo iptables -A DOCKER-SWARM -i lo -j ACCEPT
    sudo iptables -A DOCKER-SWARM -p tcp --dport 2377 -j ACCEPT
    sudo iptables -A DOCKER-SWARM -p tcp --dport 7946 -j ACCEPT
    sudo iptables -A DOCKER-SWARM -p udp --dport 7946 -j ACCEPT
    sudo iptables -A DOCKER-SWARM -p udp --dport 4789 -j ACCEPT
    sudo iptables -A DOCKER-SWARM -p icmp --icmp-type echo-request -j ACCEPT
    # Note: No DROP rule in DOCKER-SWARM chain to avoid interfering with existing rules

    # Save rules to /etc/iptables/rules.v4 for persistence
    if sudo iptables-save > /etc/iptables/rules.v4; then
        echo "IPTABLES rules saved successfully." | tee -a $LOG_FILE
    else
        echo "Error saving IPTABLES rules." | tee -a $LOG_FILE
    fi

    # Configure Docker Swarm
    if [ "$NODE_ROLE" = "manager" ]; then
        # Note: For the manager node, initializes the Swarm with the specified subnet and the node’s IP.
        echo "Initializing Docker Swarm on manager node" | tee -a $LOG_FILE
        MANAGER_IP=$(dig +short $THIS_HOST)
        if [ -z "$MANAGER_IP" ]; then
            echo "Error: Could not resolve IP for $THIS_HOST." | tee -a $LOG_FILE
            exit 1
        fi
        # Note: Initializes Swarm and captures output for debugging. Outputs the worker join token for use on other nodes.
        if docker swarm init --advertise-addr "$MANAGER_IP" --default-addr-pool "$DOCKER_SUBNET" > /tmp/swarm-init.out 2>&1; then
            echo "Docker Swarm initialized successfully." | tee -a $LOG_FILE
            JOIN_TOKEN=$(docker swarm join-token -q worker)
            echo "Worker join token: $JOIN_TOKEN" | tee -a $LOG_FILE
            echo "Run the following command on worker nodes to join the swarm:" | tee -a $LOG_FILE
            echo "docker swarm join --token $JOIN_TOKEN $MANAGER_IP:2377" | tee -a $LOG_FILE
        else
            echo "Error initializing Docker Swarm." | tee -a $LOG_FILE
            cat /tmp/swarm-init.out | tee -a $LOG_FILE
            exit 1
        fi
    else
        # Note: For worker nodes, prompts for the manager’s FQDN and join token to join the Swarm.
        echo "Joining Docker Swarm as worker node" | tee -a $LOG_FILE
        echo "Enter the manager node's FQDN:"
        read MANAGER_FQDN
        MANAGER_IP=$(dig +short $MANAGER_FQDN)
        if [ -z "$MANAGER_IP" ]; then
            echo "Error: Could not resolve IP for $MANAGER_FQDN." | tee -a $LOG_FILE
            exit 1
        fi
        echo "Enter the worker join token:"
        read JOIN_TOKEN
        # Note: Attempts to join the Swarm and logs the result for debugging.
        if docker swarm join --token "$JOIN_TOKEN" "$MANAGER_IP:2377" > /tmp/swarm-join.out 2>&1; then
            echo "Successfully joined Docker Swarm as worker." | tee -a $LOG_FILE
        else
            echo "Error joining Docker Swarm." | tee -a $LOG_FILE
            cat /tmp/swarm-join.out | tee -a $LOG_FILE
            exit 1
        fi
    fi

    # Verify Swarm status (on manager only)
    # Note: On the manager node, lists all nodes in the Swarm to confirm the cluster is operational.
    if [ "$NODE_ROLE" = "manager" ]; then
        echo "Verifying Swarm status" | tee -a $LOG_FILE
        if docker node ls > /tmp/swarm-status.out 2>&1; then
            echo "Swarm status:" | tee -a $LOG_FILE
            cat /tmp/swarm-status.out | tee -a $LOG_FILE
        else
            echo "Error retrieving Swarm status." | tee -a $LOG_FILE
            cat /tmp/swarm-status.out | tee -a $LOG_FILE
        fi
    fi

    echo "Script completed on $(date)" | tee -a $LOG_FILE
} 2>&1 | tee -a $LOG_FILE