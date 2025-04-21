#!/bin/bash

# Introduction (within script comments):
# This script deploys Portainer (Server and Agent) on a Docker Swarm cluster, using an NFS mount at /mnt/nfs/docker for persistent storage.
# It creates an overlay network, sets up the NFS directory, generates an admin password, deploys the Portainer Agent globally,
# deploys the Portainer Server on a manager node, and verifies the deployment.
# Prerequisites: Docker Swarm cluster initialized, NFS mount at /mnt/nfs/docker on all nodes, sudo privileges, Docker installed.
# The script logs all actions to /logs/deploy-portainer-YYYYMMDD.log for troubleshooting.

# Define log file name
# Note: The log file is timestamped to avoid overwrites and stored in /logs for centralized logging.
LOG_FILE="/logs/deploy-portainer-$(date '+%Y%m%d').log"

# Create Logs Directory and Log File
# Note: Ensures the /logs directory exists and creates the log file if it doesn't.
mkdir -p /logs
touch $LOG_FILE

{
    echo "Script started on $(date)" | tee -a $LOG_FILE

    # Verify sudo privileges
    # Note: Checks if the user has sudo access, as operations like creating directories and Docker commands require elevated privileges.
    if ! sudo -v; then
        echo "Error: This script requires sudo privileges." | tee -a $LOG_FILE
        exit 1
    fi

    # Verify Docker is installed
    # Note: Ensures Docker is installed and available, as the script depends on Docker commands.
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed. Please install Docker first." | tee -a $LOG_FILE
        exit 1
    fi

    # Verify Docker Swarm is initialized
    # Note: Checks if the node is part of an active Swarm cluster.
    if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
        echo "Error: This node is not part of an active Docker Swarm cluster." | tee -a $LOG_FILE
        exit 1
    fi

    # Verify node is a manager
    # Note: Ensures the script runs on a manager node, as service creation requires manager privileges.
    if ! docker node ls &> /dev/null; then
        echo "Error: This node is not a Swarm manager. Run the script on a manager node." | tee -a $LOG_FILE
        exit 1
    fi

    # Verify NFS mount
    # Note: Checks if the NFS mount at /mnt/nfs/docker exists and is accessible.
    if ! mount | grep -q "/mnt/nfs/docker"; then
        echo "Error: NFS mount at /mnt/nfs/docker is not mounted." | tee -a $LOG_FILE
        exit 1
    fi
    if ! [ -d "/mnt/nfs/docker" ] || ! [ -w "/mnt/nfs/docker" ]; then
        echo "Error: /mnt/nfs/docker is not a writable directory." | tee -a $LOG_FILE
        exit 1
    fi

    # Create NFS directory for Portainer
    # Note: Creates a subdirectory for Portainer data and sets permissive permissions for container access.
    echo "Creating NFS directory for Portainer at /mnt/nfs/docker/portainer" | tee -a $LOG_FILE
    if sudo mkdir -p /mnt/nfs/docker/portainer; then
        sudo chmod -R 777 /mnt/nfs/docker/portainer
        echo "NFS directory created and permissions set." | tee -a $LOG_FILE
    else
        echo "Error: Failed to create NFS directory /mnt/nfs/docker/portainer." | tee -a $LOG_FILE
        exit 1
    fi

    # Create overlay network for Portainer
    # Note: Creates an overlay network for communication between Portainer Server and Agents.
    echo "Creating overlay network portainer_agent_network" | tee -a $LOG_FILE
    if ! docker network ls --filter name=portainer_agent_network -q | grep -q .; then
        if docker network create \
            --driver overlay \
            --attachable \
            portainer_agent_network > /tmp/portainer-network.out 2>&1; then
            echo "Overlay network created successfully." | tee -a $LOG_FILE
        else
            echo "Error creating overlay network." | tee -a $LOG_FILE
            cat /tmp/portainer-network.out | tee -a $LOG_FILE
            exit 1
        fi
    else
        echo "Overlay network portainer_agent_network already exists." | tee -a $LOG_FILE
    fi

    # Generate admin password for Portainer
    # Note: Creates a bcrypt-hashed password file for the Portainer admin user.
    echo "Generating admin password file" | tee -a $LOG_FILE
    ADMIN_PASSWORD="your_secure_password" # Replace with a strong password
    if docker run --rm httpd:2.4 htpasswd -nbB admin "$ADMIN_PASSWORD" | cut -d ":" -f 2 > /mnt/nfs/docker/portainer/admin.pass; then
        sudo chmod 644 /mnt/nfs/docker/portainer/admin.pass
        echo "Admin password file created successfully." | tee -a $LOG_FILE
    else
        echo "Error generating admin password file." | tee -a $LOG_FILE
        exit 1
    fi

    # Deploy Portainer Agent
    # Note: Deploys the Portainer Agent as a global service to run on every node, using the NFS mount for data.
    echo "Deploying Portainer Agent" | tee -a $LOG_FILE
    if docker service create \
        --name portainer_agent \
        --network portainer_agent_network \
        --mode global \
        --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
        --mount type=bind,src=/mnt/nfs/docker/portainer,dst=/data \
        --publish mode=host,target=9001,published=9001 \
        portainer/agent:latest > /tmp/portainer-agent.out 2>&1; then
        echo "Portainer Agent deployed successfully." | tee -a $LOG_FILE
    else
        echo "Error deploying Portainer Agent." | tee -a $LOG_FILE
        cat /tmp/portainer-agent.out | tee -a $LOG_FILE
        exit 1
    fi

    # Deploy Portainer Server
    # Note: Deploys the Portainer Server as a single replica on a manager node, using the NFS mount for data.
    echo "Deploying Portainer Server" | tee -a $LOG_FILE
    if docker service create \
        --name portainer \
        --network portainer_agent_network \
        --replicas 1 \
        --mount type=bind,src=/mnt/nfs/docker/portainer,dst=/data \
        --publish published=9000,target=9000 \
        --publish published=8000,target=8000 \
        --constraint 'node.role == manager' \
        portainer/portainer-ce:latest \
        --admin-password-file=/data/admin.pass > /tmp/portainer-server.out 2>&1; then
        echo "Portainer Server deployed successfully." | tee -a $LOG_FILE
    else
        echo "Error deploying Portainer Server." | tee -a $LOG_FILE
        cat /tmp/portainer-server.out | tee -a $LOG_FILE
        exit 1
    fi

    # Wait for services to stabilize
    # Note: Waits briefly to ensure services are running before verification.
    echo "Waiting for Portainer services to stabilize" | tee -a $LOG_FILE
    sleep 10

    # Verify Portainer deployment
    # Note: Checks if Portainer services are running and logs their status.
    echo "Verifying Portainer deployment" | tee -a $LOG_FILE
    if docker service ls --filter name=portainer > /tmp/portainer-status.out 2>&1; then
        echo "Portainer services status:" | tee -a $LOG_FILE
        cat /tmp/portainer-status.out | tee -a $LOG_FILE
    else
        echo "Error retrieving Portainer services status." | tee -a $LOG_FILE
        cat /tmp/portainer-status.out | tee -a $LOG_FILE
        exit 1
    fi

    # Provide access instructions
    # Note: Outputs instructions for accessing the Portainer UI.
    MANAGER_IP=$(docker node ls --filter role=manager --format '{{.Hostname}}' | head -n 1)
    echo "Portainer deployment completed." | tee -a $LOG_FILE
    echo "Access the Portainer UI at http://$MANAGER_IP:9000" | tee -a $LOG_FILE
    echo "Login with username: admin, password: $ADMIN_PASSWORD" | tee -a $LOG_FILE
    echo "Select the Docker Swarm environment and connect to the agent via http://portainer_agent:9001" | tee -a $LOG_FILE

    echo "Script completed on $(date)" | tee -a $LOG_FILE
} 2>&1 | tee -a $LOG_FILE