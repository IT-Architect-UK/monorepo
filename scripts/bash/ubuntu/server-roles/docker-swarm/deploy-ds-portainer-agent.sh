#!/bin/bash

# Introduction (within script comments):
# This script deploys the Portainer Agent on a Docker Swarm cluster, using a user-specified storage path for persistent data.
# It checks for and offers to remove existing Portainer Agent services and images, verifies IPTABLES rules,
# creates an overlay network, sets up the storage directory, and deploys the Portainer Agent globally.
# The storage path is prompted (default: /mnt/nfs/docker/portainer) and validated for writability.
# Includes retries with timeouts, node health checks, IPTABLES validation, and detailed logging to diagnose issues.
# Prerequisites: Docker Swarm cluster initialized, storage path accessible on all nodes, sudo privileges, Docker installed.
# Logs all actions to /home/$USER/logs/deploy-portainer-agent-YYYYMMDD.log or /logs if writable.
# Note: Deploys only the Portainer Agent, assuming an existing Portainer Server instance.

# Define log file name
# Note: Uses /home/$USER/logs as fallback if /logs is not writable.
LOG_DIR="/logs"
FALLBACK_LOG_DIR="/home/$USER/logs"
LOG_FILE="$LOG_DIR/deploy-portainer-agent-$(date '+%Y%m%d').log"

# Check and set log directory
# Note: Ensures the log directory is writable, falling back to user’s home directory if needed.
if ! mkdir -p "$LOG_DIR" 2>/dev/null || ! touch "$LOG_FILE" 2>/dev/null; then
    echo "Warning: Cannot write to $LOG_DIR. Using $FALLBACK_LOG_DIR instead." | tee /dev/stderr
    LOG_DIR="$FALLBACK_LOG_DIR"
    LOG_FILE="$LOG_DIR/deploy-portainer-agent-$(date '+%Y%m%d').log"
    mkdir -p "$LOG_DIR" || { echo "Error: Cannot create $LOG_DIR."; exit 1; }
    touch "$LOG_FILE" || { echo "Error: Cannot create $LOG_FILE."; exit 1; }
fi

{
    echo "Script started on $(date)" | tee -a "$LOG_FILE"

    # Verify sudo privileges
    # Note: Checks if the user has sudo access for operations like creating directories and IPTABLES.
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

    # Verify Docker Swarm is initialized
    # Note: Checks if the node is part of an active Swarm cluster.
    SWARM_STATE=$(docker info --format '{{.Swarm.LocalNodeState}}')
    if [ "$SWARM_STATE" != "active" ]; then
        echo "Error: This node is not part of an active Docker Swarm cluster (state: $SWARM_STATE)." | tee -a "$LOG_FILE"
        exit 1
    fi

    # Verify node is a manager
    # Note: Ensures the script runs on a manager node for service creation.
    if ! docker node ls &> /dev/null; then
        echo "Error: This node is not a Swarm manager. Run the script on a manager node." | tee -a "$LOG_FILE"
        exit 1
    fi

    # Check node health
    # Note: Logs node status to ensure all nodes are ready before deployment.
    echo "Checking Swarm node health..." | tee -a "$LOG_FILE"
    docker node ls > /tmp/portainer-agent-node-status.out 2>&1
    if [ $? -eq 0 ]; then
        echo "Swarm node status:" | tee -a "$LOG_FILE"
        cat /tmp/portainer-agent-node-status.out | tee -a "$LOG_FILE"
    else
        echo "Error retrieving Swarm node status." | tee -a "$LOG_FILE"
        cat /tmp/portainer-agent-node-status.out | tee -a "$LOG_FILE"
        exit 1
    fi

    # Verify IPTABLES rules
    # Note: Ensures required Swarm and Portainer Agent ports are open.
    echo "Checking IPTABLES rules for required ports..." | tee -a "$LOG_FILE"
    REQUIRED_PORTS=("2377/tcp" "7946/tcp" "7946/udp" "4789/udp" "9001/tcp")
    for node in POSLXPDSWARM01 POSLXPDSWARM02 POSLXPDSWARM03; do
        echo "IPTABLES rules on $node:" | tee -a "$LOG_FILE"
        ssh pos-admin@$node 'sudo iptables -L DOCKER-SWARM -v -n' > /tmp/portainer-iptables-$node.out 2>&1
        cat /tmp/portainer-iptables-$node.out | tee -a "$LOG_FILE"
        for port in "${REQUIRED_PORTS[@]}"; do
            proto=$(echo $port | cut -d'/' -f2)
            port_num=$(echo $port | cut -d'/' -f1)
            if ! grep -q "dpt:$port_num" /tmp/portainer-iptables-$node.out; then
                echo "Adding IPTABLES rule for $port on $node..." | tee -a "$LOG_FILE"
                ssh pos-admin@$node "sudo iptables -A DOCKER-SWARM -p $proto --dport $port_num -j ACCEPT && sudo iptables-save > /etc/iptables/rules.v4"
            fi
        done
    done

    # Check for existing Portainer Agent service
    # Note: Prompts to remove existing portainer_agent service if it exists.
    if docker service ls --filter name=portainer_agent -q | grep -q .; then
        echo "Warning: Existing Portainer Agent service detected:" | tee -a "$LOG_FILE"
        docker service ls --filter name=portainer_agent | tee -a "$LOG_FILE"
        docker service ps portainer_agent --no-trunc | tee -a "$LOG_FILE"
        echo "Do you want to remove this service? (y/n)"
        read REMOVE_SERVICE
        if [ "$REMOVE_SERVICE" = "y" ] || [ "$REMOVE_SERVICE" = "Y" ]; then
            echo "Removing service portainer_agent..." | tee -a "$LOG_FILE"
            if docker service rm portainer_agent > /tmp/portainer-agent-service-rm.out 2>&1; then
                echo "Service portainer_agent removed successfully." | tee -a "$LOG_FILE"
            else
                echo "Error removing service portainer_agent." | tee -a "$LOG_FILE"
                cat /tmp/portainer-agent-service-rm.out | tee -a "$LOG_FILE"
                exit 1
            fi
        else
            echo "Exiting without removing existing service." | tee -a "$LOG_FILE"
            exit 1
        fi
    fi

    # Check for existing Portainer Agent image
    # Note: Prompts to remove portainer/agent:latest image if desired.
    EXISTING_IMAGES=$(docker image ls -q --filter reference='portainer/agent:latest' | sort -u | wc -l)
    if [ "$EXISTING_IMAGES" -gt 0 ]; then
        echo "Warning: Existing Portainer Agent image detected on this node:" | tee -a "$LOG_FILE"
        docker image ls portainer/agent:latest | tee -a "$LOG_FILE"
        echo "Do you want to remove this image on all nodes? (y/n)"
        read REMOVE_IMAGES
        if [ "$REMOVE_IMAGES" = "y" ] || [ "$REMOVE_IMAGES" = "Y" ]; then
            # Get all node hostnames
            NODES=$(docker node ls --format '{{.Hostname}}')
            for node in $NODES; do
                echo "Removing Portainer Agent image on $node..." | tee -a "$LOG_FILE"
                ssh pos-admin@$node 'docker rmi -f portainer/agent:latest' > /tmp/portainer-agent-image-rm-$node.out 2>&1
                if [ $? -eq 0 ]; then
                    echo "Image removed successfully on $node." | tee -a "$LOG_FILE"
                else
                    echo "Error removing image on $node (continuing)." | tee -a "$LOG_FILE"
                    cat /tmp/portainer-agent-image-rm-$node.out | tee -a "$LOG_FILE"
                fi
            done
        fi
    fi

    # Prompt for storage path
    # Note: Allows user to specify the storage path, defaulting to /mnt/nfs/docker/portainer.
    echo "Enter the storage path for Portainer Agent data (default: /mnt/nfs/docker/portainer):"
    read STORAGE_PATH
    STORAGE_PATH=${STORAGE_PATH:-/mnt/nfs/docker/portainer}
    echo "Using storage path: $STORAGE_PATH" | tee -a "$LOG_FILE"

    # Verify storage path
    # Note: Checks if the storage path is a writable directory on all nodes.
    for node in POSLXPDSWARM01 POSLXPDSWARM02 POSLXPDSWARM03; do
        echo "Verifying storage path on $node..." | tee -a "$LOG_FILE"
        if ! ssh pos-admin@$node "sudo mkdir -p \"$STORAGE_PATH\" && [ -d \"$STORAGE_PATH\" ] && [ -w \"$STORAGE_PATH\" ]"; then
            echo "Error: Storage path $STORAGE_PATH is not a writable directory on $node." | tee -a "$LOG_FILE"
            exit 1
        fi
        if ssh pos-admin@$node "mount | grep -q \"$(dirname \"$STORAGE_PATH\")\""; then
            echo "Storage path on $node appears to be on a mounted filesystem (e.g., NFS)." | tee -a "$LOG_FILE"
        fi
    done

    # Create storage directory for Portainer Agent
    # Note: Sets permissive permissions for container access.
    echo "Creating storage directory for Portainer Agent at $STORAGE_PATH" | tee -a "$LOG_FILE"
    for node in POSLXPDSWARM01 POSLXPDSWARM02 POSLXPDSWARM03; do
        if ssh pos-admin@$node "sudo mkdir -p \"$STORAGE_PATH\" && sudo chmod -R 777 \"$STORAGE_PATH\""; then
            echo "Storage directory created and permissions set on $node." | tee -a "$LOG_FILE"
        else
            echo "Error: Failed to create storage directory $STORAGE_PATH on $node." | tee -a "$LOG_FILE"
            exit 1
        fi
    done

    # Create overlay network for Portainer
    # Note: Creates an overlay network for communication with the Portainer Server.
    echo "Creating overlay network portainer_agent_network" | tee -a "$LOG_FILE"
    if ! docker network ls --filter name=portainer_agent_network -q | grep -q .; then
        if docker network create \
            --driver overlay \
            --attachable \
            portainer_agent_network > /tmp/portainer-agent-network.out 2>&1; then
            echo "Overlay network created successfully." | tee -a "$LOG_FILE"
        else
            echo "Error creating overlay network." | tee -a "$LOG_FILE"
            cat /tmp/portainer-agent-network.out | tee -a "$LOG_FILE"
            exit 1
        fi
    else
        echo "Overlay network portainer_agent_network already exists." | tee -a "$LOG_FILE"
    fi

    # Deploy Portainer Agent with retries
    # Note: Deploys the Portainer Agent as a global service with retries and a timeout.
    echo "Deploying Portainer Agent" | tee -a "$LOG_FILE"
    RETRIES=3
    ATTEMPT=1
    while [ $ATTEMPT -le $RETRIES ]; do
        echo "Attempt $ATTEMPT of $RETRIES for Portainer Agent deployment..." | tee -a "$LOG_FILE"
        if timeout 120 docker service create \
            --name portainer_agent \
            --network portainer_agent_network \
            --mode global \
            --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
            --mount type=bind,src="$STORAGE_PATH",dst=/data \
            --publish mode=host,target=9001,published=9001 \
            portainer/agent:latest > /tmp/portainer-agent.out 2>&1; then
            echo "Portainer Agent deployed successfully." | tee -a "$LOG_FILE"
            break
        else
            echo "Error deploying Portainer Agent on attempt $ATTEMPT." | tee -a "$LOG_FILE"
            cat /tmp/portainer-agent.out | tee -a "$LOG_FILE"
            if [ $ATTEMPT -eq $RETRIES ]; then
                echo "Failed to deploy Portainer Agent after $RETRIES attempts." | tee -a "$LOG_FILE"
                # Log detailed task status for debugging
                docker service ps portainer_agent --no-trunc > /tmp/portainer-agent-ps.out 2>&1
                echo "Portainer Agent task status:" | tee -a "$LOG_FILE"
                cat /tmp/portainer-agent-ps.out | tee -a "$LOG_FILE"
                # Log node details
                for node in $(docker node ls --format '{{.Hostname}}'); do
                    echo "Inspecting node $node..." | tee -a "$LOG_FILE"
                    docker node inspect $node > /tmp/portainer-node-$node.out 2>&1
                    cat /tmp/portainer-node-$node.out | tee -a "$LOG_FILE"
                done
                exit 1
            fi
            sleep 10
        fi
        ((ATTEMPT++))
    done

    # Wait for service to stabilize
    # Note: Waits briefly to ensure the service is running before verification.
    echo "Waiting for Portainer Agent service to stabilize" | tee -a "$LOG_FILE"
    sleep 10

    # Verify Portainer Agent deployment
    # Note: Checks if the Portainer Agent service is running and logs its status.
    echo "Verifying Portainer Agent deployment" | tee -a "$LOG_FILE"
    if docker service ls --filter name=portainer_agent > /tmp/portainer-agent-status.out 2>&1; then
        echo "Portainer Agent service status:" | tee -a "$LOG_FILE"
        cat /tmp/portainer-agent-status.out | tee -a "$LOG_FILE"
        echo "Portainer Agent tasks:" | tee -a "$LOG_FILE"
        docker service ps portainer_agent --no-trunc | tee -a "$LOG_FILE"
    else
        echo "Error retrieving Portainer Agent service status." | tee -a "$LOG_FILE"
        cat /tmp/portainer-agent-status.out | tee -a "$LOG_FILE"
        exit 1
    fi

    # Provide connection instructions
    # Note: Outputs instructions for connecting the Portainer Server to the agent.
    MANAGER_IP=$(docker node ls --filter role=manager --format '{{.Hostname}}' | head -n 1)
    echo "Portainer Agent deployment completed." | tee -a "$LOG_FILE"
    echo "Connect your existing Portainer Server to the agent at http://$MANAGER_IP:9001" | tee -a "$LOG_FILE"
    echo "Ensure the Portainer Server is configured to use the Swarm environment." | tee -a "$LOG_FILE"

    echo "Script completed on $(date)" | tee -a "$LOG_FILE"
} 2>&1 | tee -a "$LOG_FILE"