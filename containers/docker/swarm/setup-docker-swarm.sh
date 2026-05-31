#!/bin/bash

# Introduction (within script comments):
# This script configures a Docker Swarm cluster on Ubuntu servers, supporting a mix of manager and worker nodes.
# It prompts the user to specify if the node is the first manager (leader) or joining an existing Swarm cluster.
# If the node is already part of a Swarm, it prompts to leave before joining the new cluster.
# For the first manager, it initializes the Swarm and pauses to share manager and worker join tokens.
# For other nodes, it joins the existing Swarm using the provided leader FQDN and join token (manager or worker).
# It sets up IPTABLES firewall rules to secure Swarm communication and logs all actions to /home/$USER/logs/setup-docker-swarm-YYYYMMDD.log or /logs if writable.
# Prerequisites: Docker installed, sudo privileges, DNS-resolvable FQDNs for all nodes.
# Enhanced error handling for Docker permissions, DNS resolution, Swarm membership, and join validation.

# Define log file name
# Note: Uses /home/$USER/logs as fallback if /logs is not writable.
LOG_DIR="/logs"
FALLBACK_LOG_DIR="/home/$USER/logs"
LOG_FILE="$LOG_DIR/setup-docker-swarm-$(date '+%Y%m%d').log"

# Check and set log directory
# Note: Ensures the log directory is writable, falling back to user’s home directory if needed.
if ! mkdir -p "$LOG_DIR" 2>/dev/null || ! touch "$LOG_FILE" 2>/dev/null; then
    echo "Warning: Cannot write to $LOG_DIR. Using $FALLBACK_LOG_DIR instead." | tee /dev/stderr
    LOG_DIR="$FALLBACK_LOG_DIR"
    LOG_FILE="$LOG_DIR/setup-docker-swarm-$(date '+%Y%m%d').log"
    mkdir -p "$LOG_DIR" || { echo "Error: Cannot create $LOG_DIR."; exit 1; }
    touch "$LOG_FILE" || { echo "Error: Cannot create $LOG_FILE."; exit 1; }
fi

{
    echo "Script started on $(date)" | tee -a "$LOG_FILE"

    # Verify sudo privileges
    # Note: Checks if the user has sudo access for iptables and Docker commands.
    if ! sudo -v; then
        echo "Error: This script requires sudo privileges." | tee -a "$LOG_FILE"
        exit 1
    fi

    # Verify Docker is installed
    # Note: Ensures Docker is installed and available.
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed. Please install Docker first." | tee -a "$LOG_FILE"
        exit 1
    fi

    # Check Docker daemon access
    # Note: Verifies the user can access the Docker daemon without sudo.
    if ! docker info &> /dev/null; then
        echo "Error: Cannot access Docker daemon. Ensure you are in the 'docker' group or run with sudo." | tee -a "$LOG_FILE"
        echo "To add yourself to the docker group, run: sudo usermod -aG docker $USER && newgrp docker" | tee -a "$LOG_FILE"
        echo "Alternatively, re-run the script with sudo: sudo $0" | tee -a "$LOG_FILE"
        exit 1
    fi

    # Check if node is already in a Swarm
    # Note: Prompts to leave if the node is part of an existing Swarm.
    SWARM_STATE=$(docker info --format '{{.Swarm.LocalNodeState}}')
    if [ "$SWARM_STATE" = "active" ]; then
        echo "Warning: This node is already part of a Swarm (state: $SWARM_STATE)." | tee -a "$LOG_FILE"
        docker node ls | tee -a "$LOG_FILE"
        echo "Do you want to leave the current Swarm and join a new one? (y/n)"
        read LEAVE_SWARM
        if [ "$LEAVE_SWARM" = "y" ] || [ "$LEAVE_SWARM" = "Y" ]; then
            if docker swarm leave --force > /tmp/swarm-leave.out 2>&1; then
                echo "Successfully left the current Swarm." | tee -a "$LOG_FILE"
            else
                echo "Error leaving the current Swarm." | tee -a "$LOG_FILE"
                cat /tmp/swarm-leave.out | tee -a "$LOG_FILE"
                exit 1
            fi
        else
            echo "Exiting without modifying Swarm membership." | tee -a "$LOG_FILE"
            exit 0
        fi
    fi

    # Prompt for cluster configuration
    # Note: Collects the total number of hosts in the cluster.
    echo "Enter the number of hosts in the Docker Swarm cluster:"
    read NUM_HOSTS
    if ! [[ "$NUM_HOSTS" =~ ^[0-9]+$ ]] || [ "$NUM_HOSTS" -lt 1 ]; then
        echo "Error: Invalid number of hosts." | tee -a "$LOG_FILE"
        exit 1
    fi

    # Prompt for node role
    # Note: Supports both manager and worker roles.
    echo "Enter the role of this node (manager/worker):"
    read NODE_ROLE
    if [[ "$NODE_ROLE" != "manager" && "$NODE_ROLE" != "worker" ]]; then
        echo "Error: Role must be 'manager' or 'worker'." | tee -a "$LOG_FILE"
        exit 1
    fi

    # Collect hostnames
    # Note: Gathers FQDNs for all nodes and validates DNS resolution.
    HOSTS=()
    echo "Enter the FQDNs of all hosts in the cluster (one per line, $NUM_HOSTS total):"
    for ((i=1; i<=NUM_HOSTS; i++)); do
        read HOST
        HOSTS+=("$HOST")
        if ! ping -c 1 "$HOST" &> /dev/null; then
            echo "Warning: Could not resolve $HOST via DNS. This may cause join failures." | tee -a "$LOG_FILE"
        fi
    done

    # Prompt for private subnet
    # Note: Requests a private subnet for Docker Swarm’s overlay network.
    echo "Enter the private subnet for Docker Swarm (e.g., 10.20.0.0/16):"
    read DOCKER_SUBNET
    if ! [[ "$DOCKER_SUBNET" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        echo "Error: Invalid subnet format." | tee -a "$LOG_FILE"
        exit 1
    fi

    # Get this node's FQDN
    # Note: Retrieves the current node’s FQDN for identification.
    THIS_HOST=$(hostname -f)
    echo "This node's FQDN is $THIS_HOST" | tee -a "$LOG_FILE"

    # Configure IPTABLES firewall rules
    # Note: Creates a new chain for Docker Swarm rules to preserve existing rules.
    echo "Configuring IPTABLES firewall rules for Docker Swarm" | tee -a "$LOG_FILE"
    sudo iptables -N DOCKER-SWARM 2>/dev/null || true
    sudo iptables -F DOCKER-SWARM
    sudo iptables -C INPUT -j DOCKER-SWARM 2>/dev/null || sudo iptables -A INPUT -j DOCKER-SWARM
    sudo iptables -A DOCKER-SWARM -m state --state ESTABLISHED,RELATED -j ACCEPT
    sudo iptables -A DOCKER-SWARM -i lo -j ACCEPT
    sudo iptables -A DOCKER-SWARM -p tcp --dport 2377 -j ACCEPT
    sudo iptables -A DOCKER-SWARM -p tcp --dport 7946 -j ACCEPT
    sudo iptables -A DOCKER-SWARM -p udp --dport 7946 -j ACCEPT
    sudo iptables -A DOCKER-SWARM -p udp --dport 4789 -j ACCEPT
    sudo iptables -A DOCKER-SWARM -p icmp --icmp-type echo-request -j ACCEPT
    if sudo iptables-save > /etc/iptables/rules.v4; then
        echo "IPTABLES rules saved successfully." | tee -a "$LOG_FILE"
    else
        echo "Error saving IPTABLES rules." | tee -a "$LOG_FILE"
    fi

    # Prompt if this is the first manager or joining an existing Swarm
    # Note: Determines whether to initialize a new Swarm or join an existing one.
    echo "Is this the first manager node (leader) of the Swarm? (y/n)"
    read IS_FIRST_MANAGER
    if [ "$IS_FIRST_MANAGER" = "y" ] || [ "$IS_FIRST_MANAGER" = "Y" ]; then
        # Initialize Swarm on first manager
        echo "Initializing Docker Swarm on first manager ($THIS_HOST)" | tee -a "$LOG_FILE"
        MANAGER_IP=$(dig +short $THIS_HOST)
        if [ -z "$MANAGER_IP" ]; then
            echo "Error: Could not resolve IP for $THIS_HOST." | tee -a "$LOG_FILE"
            exit 1
        fi
        if docker swarm init --advertise-addr "$MANAGER_IP" --default-addr-pool "$DOCKER_SUBNET" > /tmp/swarm-init.out 2>&1; then
            echo "Docker Swarm initialized successfully." | tee -a "$LOG_FILE"
            MANAGER_TOKEN=$(docker swarm join-token -q manager)
            WORKER_TOKEN=$(docker swarm join-token -q worker)
            echo "Manager join token: $MANAGER_TOKEN" | tee -a "$LOG_FILE"
            echo "Worker join token: $WORKER_TOKEN" | tee -a "$LOG_FILE"
            echo "Run the following commands on other nodes to join the swarm:" | tee -a "$LOG_FILE"
            echo "For manager nodes: docker swarm join --token $MANAGER_TOKEN $MANAGER_IP:2377" | tee -a "$LOG_FILE"
            echo "For worker nodes: docker swarm join --token $WORKER_TOKEN $MANAGER_IP:2377" | tee -a "$LOG_FILE"
            echo "Press Enter to continue after copying the tokens..."
            read -r
        else
            echo "Error initializing Docker Swarm." | tee -a "$LOG_FILE"
            cat /tmp/swarm-init.out | tee -a "$LOG_FILE"
            exit 1
        fi
    else
        # Join an existing Swarm
        if [ "$NODE_ROLE" = "manager" ]; then
            echo "Joining Docker Swarm as manager node ($THIS_HOST)" | tee -a "$LOG_FILE"
            echo "Enter the leader node's FQDN (e.g., POSLXPDSWARM01):"
            read MANAGER_FQDN
            MANAGER_IP=$(dig +short $MANAGER_FQDN)
            if [ -z "$MANAGER_IP" ]; then
                echo "Error: Could not resolve IP for $MANAGER_FQDN." | tee -a "$LOG_FILE"
                exit 1
            fi
            echo "Enter the manager join token:"
            read JOIN_TOKEN
        else
            echo "Joining Docker Swarm as worker node ($THIS_HOST)" | tee -a "$LOG_FILE"
            echo "Enter the leader node's FQDN (e.g., POSLXPDSWARM01):"
            read MANAGER_FQDN
            MANAGER_IP=$(dig +short $MANAGER_FQDN)
            if [ -z "$MANAGER_IP" ]; then
                echo "Error: Could not resolve IP for $MANAGER_FQDN." | tee -a "$LOG_FILE"
                exit 1
            fi
            echo "Enter the worker join token:"
            read JOIN_TOKEN
        fi
        if docker swarm join --token "$JOIN_TOKEN" "$MANAGER_IP:2377" > /tmp/swarm-join.out 2>&1; then
            echo "Successfully joined Docker Swarm as $NODE_ROLE." | tee -a "$LOG_FILE"
        else
            echo "Error joining Docker Swarm." | tee -a "$LOG_FILE"
            cat /tmp/swarm-join.out | tee -a "$LOG_FILE"
            exit 1
        fi
    fi

    # Verify Swarm status
    # Note: Lists all nodes to confirm the cluster is operational (if manager).
    echo "Verifying Swarm status" | tee -a "$LOG_FILE"
    if docker node ls > /tmp/swarm-status.out 2>&1; then
        echo "Swarm status:" | tee -a "$LOG_FILE"
        cat /tmp/swarm-status.out | tee -a "$LOG_FILE"
    else
        echo "Warning: Cannot retrieve Swarm status (not a manager or not fully joined?)." | tee -a "$LOG_FILE"
        cat /tmp/swarm-status.out | tee -a "$LOG_FILE"
    fi

    echo "Script completed on $(date)" | tee -a "$LOG_FILE"
} 2>&1 | tee -a "$LOG_FILE"