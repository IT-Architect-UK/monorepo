#!/bin/bash

# Purpose: This script automates the installation of the Portainer agent on an Ubuntu system.
# It installs Docker if not present, pulls the latest Portainer agent image, and runs the agent container.
# Prerequisites:
# - Ubuntu system with internet access
# - User with sudo privileges
# - curl installed for fetching the latest Portainer version
# - Sufficient disk space for Docker and Portainer images (~500MB)

# Define log file name with timestamp
LOG_FILE="/logs/install-portainer-agent-$(date '+%Y%m%d_%H%M%S').log"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
    # Attempt to write to log file with sudo, but don't fail if it can't
    sudo tee -a "$LOG_FILE" >/dev/null 2>&1 <<EOF
$(date '+%Y-%m-%d %H:%M:%S') - $1
EOF
}

# Check if /logs directory exists and is writable
if ! sudo mkdir -p /logs; then
    log_message "Error: Cannot create /logs directory. Logging to stdout only."
fi

if ! sudo touch "$LOG_FILE" 2>/dev/null; then
    log_message "Error: Cannot create log file $LOG_FILE. Logging to stdout only."
fi

log_message "Script started"

# Verify sudo privileges
if ! sudo -v; then
    log_message "Error: This script requires sudo privileges."
    exit 1
fi

# Update package lists
log_message "Updating package lists"
if ! sudo apt-get update; then
    log_message "Error: Failed to update package lists."
    exit 1
fi
log_message "Successfully updated package lists."

# Install Docker if not installed
log_message "Checking if Docker is installed"
if ! command -v docker &>/dev/null; then
    log_message "Docker not found, installing Docker"
    if ! sudo apt-get install -y docker.io; then
        log_message "Error: Failed to install Docker."
        exit 1
    fi
    log_message "Docker installed successfully."

    # Start and enable Docker service
    log_message "Starting and enabling Docker service"
    if ! sudo systemctl start docker || ! sudo systemctl enable docker; then
        log_message "Error: Failed to start or enable Docker service."
        exit 1
    fi
    log_message "Docker service started and enabled."

    # Add user to docker group
    log_message "Adding user $USER to docker group"
    if ! sudo usermod -aG docker "$USER"; then
        log_message "Error: Failed to add user $USER to docker group."
        exit 1
    fi
    log_message "User $USER added to docker group. Log out and back in to apply."
else
    log_message "Docker already installed."
fi

# Clean up unused packages
log_message "Cleaning up unused packages"
if ! sudo apt-get autoremove -y; then
    log_message "Warning: Failed to clean up unused packages."
fi

# Fetch the latest Portainer agent version
log_message "Fetching the latest Portainer agent version"
LATEST_VERSION=$(curl -s https://api.github.com/repos/portainer/portainer/releases/latest | grep 'tag_name' | cut -d '"' -f 4 | sed 's/^v//')
if [ -z "$LATEST_VERSION" ]; then
    log_message "Warning: Could not fetch latest Portainer agent version. Using 2.19.1."
    LATEST_VERSION="2.19.1"
else
    log_message "Latest Portainer agent version is $LATEST_VERSION."
fi

# Pull the latest Portainer agent image
log_message "Pulling Portainer agent image (version $LATEST_VERSION)"
if ! sudo docker pull portainer/agent:"$LATEST_VERSION"; then
    log_message "Error: Failed to pull Portainer agent image."
    exit 1
fi
log_message "Portainer agent image pulled successfully."

# Run the Portainer agent container
log_message "Starting Portainer agent container"
if ! sudo docker run -d \
    -p 9001:9001 \
    --name portainer_agent \
    --restart=always \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /var/lib/docker/volumes:/var/lib/docker/volumes \
    portainer/agent:"$LATEST_VERSION"; then
    log_message "Error: FROM Failed to start Portainer agent container."
    exit 1
fi
log_message "Portainer agent container started successfully."

# Verify the container is running
log_message "Verifying Portainer agent container status"
if ! sudo docker ps --filter "name=portainer_agent" | grep -q "Up"; then
    log_message "Error: Portainer agent container is not running."
    exit 1
fi
log_message "Portainer agent container is running."

log_message "Installation completed successfully."