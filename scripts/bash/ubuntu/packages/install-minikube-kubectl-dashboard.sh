#!/bin/bash

# Brief message before sudo prompt
echo "Starting Minikube installation script. Please enter your sudo password if prompted."

# Cache sudo credentials
sudo -v
if [ $? -ne 0 ]; then
    echo "Failed to obtain sudo privileges. Exiting."
    exit 1
fi

# Generate timestamp for unique log file
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOGFILE="/logs/install_minikube_${TIMESTAMP}.log"

# Create /logs directory if it doesn't exist
if [ ! -d /logs ]; then
    sudo mkdir -p /logs
fi

# Log the full introduction
echo "=== Minikube Installation Script ===" | sudo tee -a "$LOGFILE"
echo "Purpose: Installs Minikube, kubectl, and enables the Minikube dashboard." | sudo tee -a "$LOGFILE"
echo "Target System: Ubuntu 24.04 (clean install)" | sudo tee -a "$LOGFILE"
echo "Resources Allocated: 8 CPUs, 16GB RAM for Minikube" | sudo tee -a "$LOGFILE"
echo "Requirements:" | sudo tee -a "$LOGFILE"
echo "  - Sudo privileges" | sudo tee -a "$LOGFILE"
echo "  - Internet access" | sudo tee -a "$LOGFILE"
echo "  - Minimum 32GB RAM and 16 vCPUs available" | sudo tee -a "$LOGFILE"
echo "Logs: All actions and statuses will be logged to $LOGFILE for troubleshooting." | sudo tee -a "$LOGFILE"
echo "Note: This script assumes a fresh environment and uses Docker as the Minikube driver." | sudo tee -a "$LOGFILE"
echo "=====================================" | sudo tee -a "$LOGFILE"

# Function to log commands and their output
log_command() {
    echo "Executing: $@" | sudo tee -a "$LOGFILE"
    "$@" 2>&1 | sudo tee -a "$LOGFILE"
    return ${PIPESTATUS[0]}
}

# Function to check command success
check_success() {
    local status=$1
    local message=$2
    if [ "$status" -eq 0 ]; then
        echo "$message succeeded." | sudo tee -a "$LOGFILE"
    else
        echo "$message failed. See $LOGFILE for details." | sudo tee -a "$LOGFILE"
        exit 1
    fi
}

# Update system
echo "Updating system..." | sudo tee -a "$LOGFILE"
log_command sudo apt update
check_success $? "Updating package lists"
log_command sudo apt upgrade -y
check_success $? "Upgrading system packages"

# Install dependencies
echo "Installing required dependencies..." | sudo tee -a "$LOGFILE"
log_command sudo apt install -y curl apt-transport-https ca-certificates software-properties-common
check_success $? "Installing dependencies"

# Install Docker
echo "Installing Docker..." | sudo tee -a "$LOGFILE"
log_command sudo mkdir -p /etc/apt/keyrings
check_success $? "Creating keyrings directory"
log_command curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
check_success $? "Adding Docker GPG key"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
log_command sudo apt update
check_success $? "Updating package lists with Docker repo"
log_command sudo apt install -y docker-ce docker-ce-cli containerd.io
check_success $? "Installing Docker"
log_command docker --version
check_success $? "Verifying Docker installation"

# Install kubectl
echo "Installing kubectl..." | sudo tee -a "$LOGFILE"
log_command curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
check_success $? "Downloading kubectl"
log_command chmod +x kubectl
check_success $? "Making kubectl executable"
log_command sudo mv kubectl /usr/local/bin/
check_success $? "Moving kubectl to /usr/local/bin"
log_command kubectl version --client
check_success $? "Verifying kubectl installation"

# Install Minikube
echo "Installing Minikube..." | sudo tee -a "$LOGFILE"
log_command curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
check_success $? "Downloading Minikube"
log_command chmod +x minikube
check_success $? "Making Minikube executable"
log_command sudo mv minikube /usr/local/bin/
check_success $? "Moving Minikube to /usr/local/bin"
log_command minikube version
check_success $? "Verifying Minikube installation"

# Start Minikube
echo "Starting Minikube..." | sudo tee -a "$LOGFILE"
log_command minikube start --driver=docker --cpus=8 --memory=16384
check_success $? "Starting Minikube"

# Enable Minikube dashboard
echo "Enabling Minikube dashboard..." | sudo tee -a "$LOGFILE"
log_command minikube addons enable dashboard
check_success $? "Enabling Minikube dashboard"

# Verify installation
echo "Verifying installation..." | sudo tee -a "$LOGFILE"
log_command minikube status
check_success $? "Checking Minikube status"
log_command kubectl cluster-info
check_success $? "Checking cluster info"

# Completion message
echo "=== Installation Complete ===" | sudo tee -a "$LOGFILE"
echo "Minikube, kubectl, and dashboard installed successfully." | sudo tee -a "$LOGFILE"
echo "Log file: $LOGFILE" | sudo tee -a "$LOGFILE"
echo "To access the dashboard, run: minikube dashboard --url" | sudo tee -a "$LOGFILE"
echo "For issues, review $LOGFILE and Minikube documentation." | sudo tee -a "$LOGFILE"