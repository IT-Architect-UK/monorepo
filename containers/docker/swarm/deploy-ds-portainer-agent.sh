#!/bin/bash

# Introduction (within script comments):
# This script deploys the Portainer Agent on a Docker Swarm cluster, using a user-specified storage path.
# Prompts once for SSH username and password, reusing them for all SSH and sudo commands, or uses SSH key-based authentication.
# Ensures permissions for /etc/iptables/rules.v4, checks/removes existing Portainer Agent services/images, verifies IPTABLES rules,
# creates an overlay network, sets up the storage directory, and deploys the Portainer Agent globally.
# Includes retries, node health checks, IPTABLES validation, and detailed logging.
# Prerequisites: Docker Swarm initialized, storage path accessible, sudo privileges, Docker installed, sshpass installed (if using password auth).
# Logs to /home/$USER/logs/deploy-portainer-agent-YYYYMMDD.log or /logs if writable.
# Note: Deploys only the Portainer Agent, assuming an existing Portainer Server.

# Define log file name
LOG_DIR="/logs"
FALLBACK_LOG_DIR="/home/$USER/logs"
LOG_FILE="$LOG_DIR/deploy-portainer-agent-$(date '+%Y%m%d').log"

# Check and set log directory
if ! mkdir -p "$LOG_DIR" 2>/dev/null || ! touch "$LOG_FILE" 2>/dev/null; then
    echo "Warning: Cannot write to $LOG_DIR. Using $FALLBACK_LOG_DIR instead." | tee /dev/stderr
    LOG_DIR="$FALLBACK_LOG_DIR"
    LOG_FILE="$LOG_DIR/deploy-portainer-agent-$(date '+%Y%m%d').log"
    mkdir -p "$LOG_DIR" || { echo "Error: Cannot create $LOG_DIR."; exit 1; }
    touch "$LOG_FILE" || { echo "Error: Cannot create $LOG_FILE."; exit 1; }
fi

{
    echo "Script started on $(date)" | tee -a "$LOG_FILE"

    # Prompt for SSH credentials
    echo "Enter the SSH username:"
    read SSH_USERNAME
    if [ -z "$SSH_USERNAME" ]; then
        echo "Error: Username cannot be empty." | tee -a "$LOG_FILE"
        exit 1
    fi

    # Check for sshpass and authentication method
    USE_SSH_KEYS="n"
    if ! command -v sshpass &> /dev/null; then
        echo "Warning: sshpass is not installed, required for password-based SSH authentication." | tee -a "$LOG_FILE"
        echo "Do you want to install sshpass? (y/n)"
        read INSTALL_SSHPASS
        if [ "$INSTALL_SSHPASS" = "y" ] || [ "$INSTALL_SSHPASS" = "Y" ]; then
            sudo apt-get update
            sudo apt-get install -y sshpass || { echo "Error: Failed to install sshpass." | tee -a "$LOG_FILE"; exit 1; }
        else
            echo "Do you want to use SSH key-based authentication instead? (y/n)"
            read USE_SSH_KEYS
            if [ "$USE_SSH_KEYS" != "y" ] && [ "$USE_SSH_KEYS" != "Y" ]; then
                echo "Error: sshpass is required for password-based authentication. Exiting." | tee -a "$LOG_FILE"
                exit 1
            fi
        fi
    fi

    # Prompt for password if not using SSH keys
    if [ "$USE_SSH_KEYS" != "y" ] && [ "$USE_SSH_KEYS" != "Y" ]; then
        echo "Enter the password for $SSH_USERNAME (used for SSH and sudo):"
        read -s SSH_PASSWORD
        if [ -z "$SSH_PASSWORD" ]; then
            echo "Error: Password cannot be empty." | tee -a "$LOG_FILE"
            exit 1
        fi
    fi

    # Verify SSH and sudo access
    NODES=("POSLXPDSWARM01" "POSLXPDSWARM02" "POSLXPDSWARM03")
    for node in "${NODES[@]}"; do
        echo "Verifying SSH and sudo access on $node..." | tee -a "$LOG_FILE"
        if [ "$USE_SSH_KEYS" = "y" ] || [ "$USE_SSH_KEYS" = "Y" ]; then
            if ssh -o StrictHostKeyChecking=no $SSH_USERNAME@$node "sudo -n whoami" > /tmp/ssh-test-$node.out 2>&1; then
                echo "SSH key-based and sudo access verified on $node." | tee -a "$LOG_FILE"
            else
                echo "Error: Failed to verify SSH or sudo access on $node with SSH keys." | tee -a "$LOG_FILE"
                cat /tmp/ssh-test-$node.out | tee -a "$LOG_FILE"
                exit 1
            fi
        else
            if sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no $SSH_USERNAME@$node "echo '$SSH_PASSWORD' | sudo -S whoami" > /tmp/ssh-test-$node.out 2>&1; then
                echo "SSH and sudo access verified on $node." | tee -a "$LOG_FILE"
            else
                echo "Error: Failed to verify SSH or sudo access on $node." | tee -a "$LOG_FILE"
                cat /tmp/ssh-test-$node.out | tee -a "$LOG_FILE"
                exit 1
            fi
        fi
    done

    # Verify local sudo privileges
    if ! sudo -v; then
        echo "Error: This script requires sudo privileges locally." | tee -a "$LOG_FILE"
        exit 1
    fi

    # Verify Docker is installed
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker is not installed. Please install Docker first." | tee -a "$LOG_FILE"
        exit 1
    fi

    # Check Docker daemon access
    if ! docker info &> /dev/null; then
        echo "Error: Cannot access Docker daemon. Ensure you are in the 'docker' group or run with sudo." | tee -a "$LOG_FILE"
        exit 1
    fi

    # Verify Docker Swarm is initialized
    SWARM_STATE=$(docker info --format '{{.Swarm.LocalNodeState}}')
    if [ "$SWARM_STATE" != "active" ]; then
        echo "Error: This node is not part of an active Docker Swarm cluster (state: $SWARM_STATE)." | tee -a "$LOG_FILE"
        exit 1
    fi

    # Verify node is a manager
    if ! docker node ls &> /dev/null; then
        echo "Error: This node is not a Swarm manager. Run the script on a manager node." | tee -a "$LOG_FILE"
        exit 1
    fi

    # Check node health
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

    # Fix IPTABLES permissions
    echo "Fixing IPTABLES permissions on all nodes..." | tee -a "$LOG_FILE"
    for node in "${NODES[@]}"; do
        if [ "$USE_SSH_KEYS" = "y" ] || [ "$USE_SSH_KEYS" = "Y" ]; then
            ssh -o StrictHostKeyChecking=no $SSH_USERNAME@$node "sudo -n mkdir -p /etc/iptables && sudo -n touch /etc/iptables/rules.v4 && sudo -n chown root:root /etc/iptables /etc/iptables/rules.v4 && sudo -n chmod 644 /etc/iptables/rules.v4 && sudo -n chmod 755 /etc/iptables" || {
                echo "Error fixing IPTABLES permissions on $node." | tee -a "$LOG_FILE"
                exit 1
            }
        else
            sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no $SSH_USERNAME@$node "echo '$SSH_PASSWORD' | sudo -S mkdir -p /etc/iptables && echo '$SSH_PASSWORD' | sudo -S touch /etc/iptables/rules.v4 && echo '$SSH_PASSWORD' | sudo -S chown root:root /etc/iptables /etc/iptables/rules.v4 && echo '$SSH_PASSWORD' | sudo -S chmod 644 /etc/iptables/rules.v4 && echo '$SSH_PASSWORD' | sudo -S chmod 755 /etc/iptables" || {
                echo "Error fixing IPTABLES permissions on $node." | tee -a "$LOG_FILE"
                exit 1
            }
        fi
    done

    # Verify IPTABLES rules
    echo "Checking IPTABLES rules for required ports..." | tee -a "$LOG_FILE"
    REQUIRED_PORTS=("2377/tcp" "7946/tcp" "7946/udp" "4789/udp" "9001/tcp")
    for node in "${NODES[@]}"; do
        echo "IPTABLES rules on $node:" | tee -a "$LOG_FILE"
        if [ "$USE_SSH_KEYS" = "y" ] || [ "$USE_SSH_KEYS" = "Y" ]; then
            ssh -o StrictHostKeyChecking=no $SSH_USERNAME@$node "sudo -n iptables -L DOCKER-SWARM -v -n" > /tmp/portainer-iptables-$node.out 2>&1
        else
            sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no $SSH_USERNAME@$node "echo '$SSH_PASSWORD' | sudo -S iptables -L DOCKER-SWARM -v -n" > /tmp/portainer-iptables-$node.out 2>&1
        fi
        if [ $? -eq 0 ]; then
            cat /tmp/portainer-iptables-$node.out | tee -a "$LOG_FILE"
            for port in "${REQUIRED_PORTS[@]}"; do
                proto=$(echo $port | cut -d'/' -f2)
                port_num=$(echo $port | cut -d'/' -f1)
                if ! grep -q "dpt:$port_num" /tmp/portainer-iptables-$node.out; then
                    echo "Adding IPTABLES rule for $port on $node..." | tee -a "$LOG_FILE"
                    if [ "$USE_SSH_KEYS" = "y" ] || [ "$USE_SSH_KEYS" = "Y" ]; then
                        ssh -o StrictHostKeyChecking=no $SSH_USERNAME@$node "sudo -n iptables -A DOCKER-SWARM -p $proto --dport $port_num -j ACCEPT && sudo -n iptables-save > /etc/iptables/rules.v4" || {
                            echo "Error adding IPTABLES rule for $port on $node." | tee -a "$LOG_FILE"
                            exit 1
                        }
                    else
                        sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no $SSH_USERNAME@$node "echo '$SSH_PASSWORD' | sudo -S iptables -A DOCKER-SWARM -p $proto --dport $port_num -j ACCEPT && echo '$SSH_PASSWORD' | sudo -S iptables-save > /etc/iptables/rules.v4" || {
                            echo "Error adding IPTABLES rule for $port on $node." | tee -a "$LOG_FILE"
                            exit 1
                        }
                    fi
                fi
            done
        else
            echo "Error checking IPTABLES rules on $node." | tee -a "$LOG_FILE"
            cat /tmp/portainer-iptables-$node.out | tee -a "$LOG_FILE"
            exit 1
        fi
    done

    # Check for existing Portainer Agent service
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
    EXISTING_IMAGES=$(docker image ls -q --filter reference='portainer/agent:latest' | sort -u | wc -l)
    if [ "$EXISTING_IMAGES" -gt 0 ]; then
        echo "Warning: Existing Portainer Agent image detected on this node:" | tee -a "$LOG_FILE"
        docker image ls portainer/agent:latest | tee -a "$LOG_FILE"
        echo "Do you want to remove this image on all nodes? (y/n)"
        read REMOVE_IMAGES
        if [ "$REMOVE_IMAGES" = "y" ] || [ "$REMOVE_IMAGES" = "Y" ]; then
            for node in "${NODES[@]}"; do
                echo "Removing Portainer Agent image on $node..." | tee -a "$LOG_FILE"
                if [ "$USE_SSH_KEYS" = "y" ] || [ "$USE_SSH_KEYS" = "Y" ]; then
                    ssh -o StrictHostKeyChecking=no $SSH_USERNAME@$node 'docker rmi -f portainer/agent:latest' > /tmp/portainer-agent-image-rm-$node.out 2>&1
                else
                    sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no $SSH_USERNAME@$node 'docker rmi -f portainer/agent:latest' > /tmp/portainer-agent-image-rm-$node.out 2>&1
                fi
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
    echo "Enter the storage path for Portainer Agent data (default: /mnt/nfs/docker/portainer):"
    read STORAGE_PATH
    STORAGE_PATH=${STORAGE_PATH:-/mnt/nfs/docker/portainer}
    echo "Using storage path: $STORAGE_PATH" | tee -a "$LOG_FILE"

    # Verify storage path
    for node in "${NODES[@]}"; do
        echo "Verifying storage path on $node..." | tee -a "$LOG_FILE"
        if [ "$USE_SSH_KEYS" = "y" ] || [ "$USE_SSH_KEYS" = "Y" ]; then
            if ! ssh -o StrictHostKeyChecking=no $SSH_USERNAME@$node "sudo -n mkdir -p \"$STORAGE_PATH\" && [ -d \"$STORAGE_PATH\" ] && [ -w \"$STORAGE_PATH\" ]"; then
                echo "Error: Storage path $STORAGE_PATH is not a writable directory on $node." | tee -a "$LOG_FILE"
                exit 1
            fi
            if ssh -o StrictHostKeyChecking=no $SSH_USERNAME@$node "mount | grep -q \"$(dirname \"$STORAGE_PATH\")\""; then
                echo "Storage path on $node appears to be on a mounted filesystem (e.g., NFS)." | tee -a "$LOG_FILE"
            fi
        else
            if ! sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no $SSH_USERNAME@$node "echo '$SSH_PASSWORD' | sudo -S mkdir -p \"$STORAGE_PATH\" && [ -d \"$STORAGE_PATH\" ] && [ -w \"$STORAGE_PATH\" ]"; then
                echo "Error: Storage path $STORAGE_PATH is not a writable directory on $node." | tee -a "$LOG_FILE"
                exit 1
            fi
            if sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no $SSH_USERNAME@$node "mount | grep -q \"$(dirname \"$STORAGE_PATH\")\""; then
                echo "Storage path on $node appears to be on a mounted filesystem (e.g., NFS)." | tee -a "$LOG_FILE"
            fi
        fi
    done

    # Create storage directory for Portainer Agent
    echo "Creating storage directory for Portainer Agent at $STORAGE_PATH" | tee -a "$LOG_FILE"
    for node in "${NODES[@]}"; do
        if [ "$USE_SSH_KEYS" = "y" ] || [ "$USE_SSH_KEYS" = "Y" ]; then
            if ssh -o StrictHostKeyChecking=no $SSH_USERNAME@$node "sudo -n mkdir -p \"$STORAGE_PATH\" && sudo -n chmod -R 777 \"$STORAGE_PATH\""; then
                echo "Storage directory created and permissions set on $node." | tee -a "$LOG_FILE"
            else
                echo "Error: Failed to create storage directory $STORAGE_PATH on $node." | tee -a "$LOG_FILE"
                exit 1
            fi
        else
            if sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no $SSH_USERNAME@$node "echo '$SSH_PASSWORD' | sudo -S mkdir -p \"$STORAGE_PATH\" && echo '$SSH_PASSWORD' | sudo -S chmod -R 777 \"$STORAGE_PATH\""; then
                echo "Storage directory created and permissions set on $node." | tee -a "$LOG_FILE"
            else
                echo "Error: Failed to create storage directory $STORAGE_PATH on $node." | tee -a "$LOG_FILE"
                exit 1
            fi
        fi
    done

    # Create overlay network for Portainer
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
                docker service ps portainer_agent --no-trunc > /tmp/portainer-agent-ps.out 2>&1
                echo "Portainer Agent task status:" | tee -a "$LOG_FILE"
                cat /tmp/portainer-agent-ps.out | tee -a "$LOG_FILE"
                for node in "${NODES[@]}"; do
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
    echo "Waiting for Portainer Agent service to stabilize" | tee -a "$LOG_FILE"
    sleep 10

    # Verify Portainer Agent deployment
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
    MANAGER_IP=$(docker node ls --filter role=manager --format '{{.Hostname}}' | head -n 1)
    echo "Portainer Agent deployment completed." | tee -a "$LOG_FILE"
    echo "Connect your existing Portainer Server to the agent at http://$MANAGER_IP:9001" | tee -a "$LOG_FILE"
    echo "Ensure the Portainer Server is configured to use the Swarm environment." | tee -a "$LOG_FILE"

    echo "Script completed on $(date)" | tee -a "$LOG_FILE"
} 2>&1 | tee -a "$LOG_FILE"