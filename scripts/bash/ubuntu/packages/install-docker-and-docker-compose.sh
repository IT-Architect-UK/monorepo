#!/bin/bash

# Define log file name
LOG_FILE="/logs/install-docker-$(date '+%Y%m%d').log"

# Create Logs Directory and Log File
mkdir -p /logs
touch $LOG_FILE

{
    echo "Script started on $(date)" | tee -a $LOG_FILE

    # Verify sudo privileges
    if ! sudo -v; then
        echo "Error: This script requires sudo privileges." | tee -a $LOG_FILE
    fi

    # Update package lists
    echo "Updating Package Lists" | tee -a $LOG_FILE
    if sudo apt-get update; then
        echo "Successfully updated package lists." | tee -a $LOG_FILE
    else
        echo "Error occurred while updating package lists." | tee -a $LOG_FILE
    fi

    # Install prerequisites
    echo "Installing prerequisites for Docker" | tee -a $LOG_FILE
    if sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release; then
        echo "Prerequisites installed successfully." | tee -a $LOG_FILE
    else
        echo "Error installing prerequisites." | tee -a $LOG_FILE
    fi

    # Add Docker's official GPG key
    echo "Adding Docker's official GPG key" | tee -a $LOG_FILE
    if curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg; then
        echo "Docker GPG key added successfully." | tee -a $LOG_FILE
    else
        echo "Error adding Docker GPG key." | tee -a $LOG_FILE
    fi

    # Add Docker repository to APT sources
    echo "Adding Docker repository to APT sources" | tee -a $LOG_FILE
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    if sudo apt-get update; then
        echo "Docker repository added and updated successfully." | tee -a $LOG_FILE
    else
        echo "Error updating after adding Docker repository." | tee -a $LOG_FILE
    fi

    # Install Docker
    echo "Installing Docker" | tee -a $LOG_FILE
    if sudo apt-get install -y docker-ce docker-ce-cli containerd.io; then
        echo "Docker installed successfully." | tee -a $LOG_FILE
    else
        echo "Error installing Docker." | tee -a $LOG_FILE
    fi

    # Verify Docker installation
    echo "Verifying Docker installation" | tee -a $LOG_FILE
    if sudo docker run hello-world; then
        echo "Docker installation verified successfully." | tee -a $LOG_FILE
    else
        echo "Error verifying Docker installation." | tee -a $LOG_FILE
    fi

    # Install Docker Compose
    echo "Installing Docker Compose" | tee -a $LOG_FILE
    # Get the latest version of Docker Compose
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    if sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose; then
        # Make it executable
        sudo chmod +x /usr/local/bin/docker-compose
        echo "Docker Compose installed successfully." | tee -a $LOG_FILE
    else
        echo "Error installing Docker Compose." | tee -a $LOG_FILE
    fi

    # Verify Docker Compose installation
    echo "Verifying Docker Compose installation" | tee -a $LOG_FILE
    if docker-compose --version; then
        echo "Docker Compose installation verified successfully." | tee -a $LOG_FILE
    else
        echo "Error verifying Docker Compose installation." | tee -a $LOG_FILE
    fi

    echo "Script completed on $(date)" | tee -a $LOG_FILE
} 2>&1 | tee -a $LOG_FILE