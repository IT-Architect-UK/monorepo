#!/bin/bash

# Introduction (within script comments):
# This script deploys Portainer (Server and Agent) on a Docker Swarm cluster, using a user-specified storage path for persistent data.
# It creates an overlay network, sets up the storage directory, generates an admin password, deploys the Portainer Agent globally,
# deploys the Portainer Server on a manager node, and verifies the deployment.
# The storage path is prompted (default: /mnt/nfs/docker/portainer) and validated for writability.
# Prerequisites: Docker Swarm cluster initialized, storage path accessible on all nodes, sudo privileges, Docker installed.
# The script logs all actions to /home/$USER/logs/deploy-portainer-YYYYMMDD.log or /logs if writable.
# Enhanced error handling with timeouts and detailed logging to prevent hanging.

# Define log file name
# Note: Uses /home/$USER/logs as fallback if /logs is not writable.
LOG_DIR="/logs"
FALLBACK_LOG_DIR="/home/$USER/logs"
LOG_FILE="$LOG_DIR/deploy-portainer-$(date '+%Y%m%d').log"

# Check and set log directory
# Note: Ensures the log directory is writable, falling back to user’s home directory if needed.
if ! mkdir -p "$LOG_DIR" 2>/dev/null || ! touch "$LOG_FILE" 2>/dev/null; then
    echo "Warning: Cannot write to $LOG_DIR. Using $FALLBACK_LOG_DIR instead." | tee /dev/stderr
    LOG_DIR="$FALLBACK_LOG_DIR"
    LOG_FILE="$LOG_DIR/deploy-portainer-$(date '+%Y%m%d').log"
    mkdir -p "$LOG_DIR" || { echo "Error: Cannot create $LOG_DIR."; exit 1; }
    touch "$LOG_FILE" || { echo "Error: Cannot create $LOG_FILE."; exit 1; }
fi

{
    echo "Script started on $(date)" | tee -a "$LOG_FILE"

    # Verify sudo privileges
    # Note: Checks if the user has sudo access for operations like creating directories.
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

    # Prompt for storage path
    # Note: Allows user to specify the storage path, defaulting to /mnt/nfs/docker/portainer.
    echo "Enter the storage path for Portainer data (default: /mnt/nfs/docker/portainer):"
    read STORAGE_PATH
    STORAGE_PATH=${STORAGE_PATH:-/mnt/nfs/docker/portainer}
    echo "Using storage path: $STORAGE_PATH" | tee -a "$LOG_FILE"

    # Verify storage path
    # Note: Checks if the storage path is a writable directory.
    if ! sudo mkdir -p "$STORAGE_PATH" || ! [ -d "$STORAGE_PATH" ] || ! [ -w "$STORAGE_PATH" ]; then
        echo "Error: Storage path $STORAGE_PATH is not a writable directory." | tee -a "$LOG_FILE"
        exit 1
    fi
    if mount | grep -q "$(dirname "$STORAGE_PATH")"; then
        echo "Storage path appears to be on a mounted filesystem (e.g., NFS)." | tee -a "$LOG_FILE"
    fi

    # Create storage directory for Portainer
    # Note: Sets permissive permissions for container access.
    echo "Creating storage directory for Portainer at $STORAGE_PATH" | tee -a "$LOG_FILE"
    if sudo mkdir -p "$STORAGE_PATH"; then
        sudo chmod -R 777 "$STORAGE_PATH"
        echo "Storage directory created and permissions set." | tee -a "$LOG_FILE"
    else
        echo "Error: Failed to create storage directory $STORAGE_PATH." | tee -a "$LOG_FILE"
        exit 1
    fi

    # Create overlay network for Portainer
    # Note: Creates an overlay network for communication between Portainer Server and Agents.
    echo "Creating overlay network portainer_agent_network" | tee -a "$LOG_FILE"
    if ! docker network ls --filter name=portainer_agent_network -q | grep -q .; then
        if docker network create \
            --driver overlay \
            --attachable \
            portainer_agent_network > /tmp/portainer-network.out 2>&1; then
            echo "Overlay network created successfully." | tee -a "$LOG_FILE"
        else
            echo "Error creating overlay network." | tee -a "$LOG_FILE"
            cat /tmp/portainer-network.out | tee -a "$LOG_FILE"
            exit 1
        fi
    else
        echo "Overlay network portainer_agent_network already exists." | tee -a "$LOG_FILE"
    fi

    # Generate admin password for Portainer
    # Note: Prompts for the admin password and creates a bcrypt-hashed password file.
    echo "Enter the Portainer admin password:" | tee -a "$LOG_FILE"
    read -s ADMIN_PASSWORD
    if [ -z "$ADMIN_PASSWORD" ]; then
        echo "Error: Admin password cannot be empty." | tee -a "$LOG_FILE"
        exit 1
    fi
    echo "Generating admin password file" | tee -a "$LOG_FILE"
    if docker run --rm httpd:2.4 htpasswd -nbB admin "$ADMIN_PASSWORD" | cut -d ":" -f 2 > "$STORAGE_PATH/admin.pass"; then
        sudo chmod 644 "$STORAGE_PATH/admin.pass"
        echo "Admin password file created successfully." | tee -a "$LOG_FILE"
    else
        echo "Error generating admin password file." | tee -a "$LOG_FILE"
        exit 1
    fi

    # Deploy Portainer Agent
    # Note: Deploys the Portainer Agent as a global service with a timeout.
    echo "Deploying Portainer Agent" | tee -a "$LOG_FILE"
    if timeout 300 docker service create \
        --name portainer_agent \
        --network portainer_agent_network \
        --mode global \
        --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
        --mount type=bind,src="$STORAGE_PATH",dst=/data \
        --publish mode=host,target=9001,published=9001 \
        portainer/agent:latest > /tmp/portainer-agent.out 2>&1; then
        echo "Portainer Agent deployed successfully." | tee -a "$LOG_FILE"
    else
        echo "Error deploying Portainer Agent (possible timeout or failure)." | tee -a "$LOG_FILE"
        cat /tmp/portainer-agent.out | tee -a "$LOG_FILE"
        exit 1
    fi

    # Deploy Portainer Server
    # Note: Deploys the Portainer Server as a single replica with a timeout.
    echo "Deploying Portainer Server" | tee -a "$LOG_FILE"
    if timeout 300 docker service create \
        --name portainer \
        --network portainer_agent_network \
        --replicas 1 \
        --mount type=bind,src="$STORAGE_PATH",dst=/data \
        --publish published=9000,target=9000 \
        --publish published=8000,target=8000 \
        --constraint 'node.role == manager' \
        portainer/portainer-ce:latest \
        --admin-password-file=/data/admin.pass > /tmp/portainer-server.out 2>&1; then
        echo "Portainer Server deployed successfully." | tee -a "$LOG_FILE"
    else
        echo "Error deploying Portainer Server (possible timeout or failure)." | tee -a "$LOG_FILE"
        cat /tmp/portainer-server.out | tee -a "$LOG_FILE"
        exit 1
    fi

    # Wait for services to stabilize
    # Note: Waits briefly to ensure services are running before verification.
    echo "Waiting for Portainer services to stabilize" | tee -a "$LOG_FILE"
    sleep 10

    # Verify Portainer deployment
    # Note: Checks if Portainer services are running and logs their status.
    echo "Verifying Portainer deployment" | tee -a "$LOG_FILE"
    if docker service ls --filter name=portainer > /tmp/portainer-status.out 2>&1; then
        echo "Portainer services status:" | tee -a "$LOG_FILE"
        cat /tmp/portainer-status.out | tee -a "$LOG_FILE"
        # Log detailed service status
        echo "Portainer Agent tasks:" | tee -a "$LOG_FILE"
        docker service ps portainer_agent | tee -a "$LOG_FILE"
        echo "Portainer Server tasks:" | tee -a "$LOG_FILE"
        docker service ps portainer | tee -a "$LOG_FILE"
    else
        echo "Error retrieving Portainer services status." | tee -a "$LOG_FILE"
        cat /tmp/portainer-status.out | tee -a "$LOG_FILE"
        exit 1
    fi

    # Provide access instructions
    # Note: Outputs instructions for accessing the Portainer UI.
    MANAGER_IP=$(docker node ls --filter role=manager --format '{{.Hostname}}' | head -n 1)
    echo "Portainer deployment completed." | tee -a "$LOG_FILE"
    echo "Access the Portainer UI at http://$MANAGER_IP:9000" | tee -a "$LOG_FILE"
    echo "Login with username: admin and the password you provided." | tee -a "$LOG_FILE"
    echo "Select the Docker Swarm environment and connect to the agent via http://portainer_agent:9001" | tee -a "$LOG_FILE"

    echo "Script completed on $(date)" | tee -a "$LOG_FILE"
} 2>&1 | tee -a "$LOG_FILE"