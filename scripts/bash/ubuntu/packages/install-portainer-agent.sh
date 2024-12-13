#!/bin/bash

# Define log file name with more specific naming
LOG_FILE="/logs/install-portainer-agent-$(date '+%Y%m%d_%H%M%S').log"

# Create Logs Directory and Log File
mkdir -p /logs
touch $LOG_FILE

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a $LOG_FILE
}

{
    log_message "Script started"

    # Verify sudo privileges
    if ! sudo -v; then
        log_message "Error: This script requires sudo privileges."
        exit 1
    fi

    # Update package lists
    log_message "Updating package lists"
    if sudo apt-get update; then
        log_message "Successfully updated package lists."
    else
        log_message "Error occurred while updating package lists."
        exit 1
    fi

    # Install Docker if not installed (assuming Docker is required for Portainer)
    log_message "Checking if Docker is installed"
    if ! command -v docker &> /dev/null; then
        log_message "Docker not found, installing Docker"
        if sudo apt-get install -y docker.io; then
            log_message "Docker installed successfully."
        else
            log_message "Error installing Docker."
            exit 1
        fi
    else
        log_message "Docker already installed."
    fi

    # Pull the latest Portainer agent image
    log_message "Pulling Portainer agent image"
    if sudo docker pull portainer/agent:2.19.1; then
        log_message "Portainer agent image pulled successfully."
    else
        log_message "Error pulling Portainer agent image."
        exit 1
    fi

    # Run the Portainer agent container
    log_message "Starting Portainer agent container"
    if sudo docker run -d \
      -p 9001:9001 \
      --name portainer_agent \
      --restart=always \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v /var/lib/docker/volumes:/var/lib/docker/volumes \
      portainer/agent:2.19.1; then
        log_message "Portainer agent container started successfully."
    else
        log_message "Error starting Portainer agent container."
        exit 1
    fi

    # Verify the container is running
    log_message "Verifying Portainer agent container status"
    if sudo docker ps --filter "name=portainer_agent" | grep -q "Up"; then
        log_message "Portainer agent container is running."
    else
        log_message "Portainer agent container is not running."
        exit 1
    fi

    log_message "Installation completed."
} || {
    log_message "Script terminated with errors."
    exit 1
}
