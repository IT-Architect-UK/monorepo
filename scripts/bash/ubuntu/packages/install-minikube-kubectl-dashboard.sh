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

# Function to log messages
log() {
    echo "$@" | sudo tee -a "$LOGFILE"
}

# Function to run commands and log output
log_command() {
    local cmd="$1"
    echo "Executing: $cmd" | sudo tee -a "$LOGFILE"
    output=$(bash -c "$cmd" 2>&1)
    status=$?
    echo "$output" | sudo tee -a "$LOGFILE"
    return $status
}

# Function to check command success
check_success() {
    local status=$1
    local message=$2
    if [ "$status" -eq 0 ]; then
        log "$message succeeded."
    else
        log "$message failed. See $LOGFILE for details."
        exit 1
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" > /dev/null 2>&1
}

# Log the introduction
log "=== Minikube Installation Script ==="
log "Purpose: Installs Minikube, kubectl, and enables the Minikube dashboard."
log "Target System: Ubuntu 24.04 (clean install)"
log "Resources Allocated: 8 CPUs, 16GB RAM for Minikube"
log "Requirements:"
log "  - Sudo privileges"
log "  - Internet access"
log "  - Minimum 32GB RAM and 16 vCPUs available"
log "Logs: All actions and statuses will be logged to $LOGFILE for troubleshooting."
log "Note: This script assumes a fresh environment and uses Docker as the Minikube driver."
log "====================================="

# Check write permissions for /tmp
log "Checking write permissions for /tmp..."
if ! touch /tmp/test_write 2>/dev/null; then
    log "Cannot write to /tmp. Check permissions."
    exit 1
fi
rm -f /tmp/test_write
log "Write permissions for /tmp confirmed."

# Check if Docker is installed
if ! command_exists docker; then
    log "Installing Docker..."
    # Update system
    log_command "sudo apt update"
    check_success $? "apt update"
    # Install dependencies
    log_command "sudo apt install -y curl apt-transport-https ca-certificates software-properties-common"
    check_success $? "Installing dependencies"
    # Set up Docker repository
    log_command "sudo mkdir -p /etc/apt/keyrings"
    check_success $? "Creating keyrings directory"
    # Verify Docker GPG key URL
    if ! curl -I -s -f https://download.docker.com/linux/ubuntu/gpg > /dev/null; then
        log "Docker GPG key URL is not reachable. Check internet connection."
        exit 1
    fi
    log_command "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
    check_success $? "Adding Docker GPG key"
    log_command "echo 'deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable' | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null"
    check_success $? "Adding Docker repository"
    log_command "sudo apt update"
    check_success $? "apt update after adding Docker repository"
    # Install Docker
    log_command "sudo apt install -y docker-ce docker-ce-cli containerd.io"
    check_success $? "Installing Docker"
    log_command "docker --version"
    check_success $? "Checking Docker version"
else
    log "Docker is already installed."
fi

# Verify docker group exists
if ! getent group docker > /dev/null; then
    log "Docker group does not exist after installation. Something went wrong."
    exit 1
fi

# Check if user is in docker group
if ! groups | grep -q docker; then
    log "Adding user to docker group..."
    sudo usermod -aG docker "$USER"
    if [ $? -ne 0 ]; then
        log "Failed to add user to docker group. Check if the group exists."
        exit 1
    fi
    log "Please log out and log back in for the group changes to take effect, then run this script again."
    exit 0
fi

# Install kubectl if not exists
if ! command_exists kubectl; then
    log "Installing kubectl..."
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    log_command "curl -L \"https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl\" -o /tmp/kubectl"
    check_success $? "Downloading kubectl"
    if [ ! -f /tmp/kubectl ]; then
        log "kubectl file not found in /tmp after download."
        exit 1
    fi
    log_command "chmod +x /tmp/kubectl"
    check_success $? "Making kubectl executable"
    log_command "sudo mv /tmp/kubectl /usr/local/bin/"
    check_success $? "Moving kubectl to /usr/local/bin"
    log_command "kubectl version --client"
    check_success $? "Checking kubectl version"
else
    log "kubectl is already installed."
fi

# Install minikube if not exists
if ! command_exists minikube; then
    log "Installing minikube..."
    log_command "curl -L https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 -o /tmp/minikube"
    check_success $? "Downloading minikube"
    if [ ! -f /tmp/minikube ]; then
        log "minikube file not found in /tmp after download."
        exit 1
    fi
    log_command "chmod +x /tmp/minikube"
    check_success $? "Making minikube executable"
    log_command "sudo mv /tmp/minikube /usr/local/bin/"
    check_success $? "Moving minikube to /usr/local/bin"
    log_command "minikube version"
    check_success $? "Checking minikube version"
else
    log "minikube is already installed."
fi

# Check available resources
log "Checking available resources..."
AVAILABLE_CPUS=$(nproc)
AVAILABLE_MEM=$(free -m | awk '/^Mem:/{print $2}')
log "Available CPUs: $AVAILABLE_CPUS"
log "Available memory: $AVAILABLE_MEM MB"
if [ "$AVAILABLE_CPUS" -lt 8 ]; then
    log "Warning: Available CPUs less than 8. Minikube may not perform optimally."
fi
if [ "$AVAILABLE_MEM" -lt 16384 ]; then
    log "Warning: Available memory less than 16GB. Minikube may not perform optimally."
fi

# Start Minikube
log "Starting Minikube..."
log_command "minikube start --driver=docker --cpus=8 --memory=16384"
check_success $? "Starting Minikube"

# Enable Minikube dashboard
log "Enabling Minikube dashboard..."
log_command "minikube addons enable dashboard"
check_success $? "Enabling Minikube dashboard"

# Enable metrics-server addon
log "Enabling metrics-server addon..."
log_command "minikube addons enable metrics-server"
check_success $? "Enabling metrics-server addon"

# Start Minikube dashboard proxy for LAN access
log "Starting Minikube dashboard proxy for LAN access..."
log_command "minikube dashboard --url --bind-address=0.0.0.0 > /tmp/dashboard_url.txt 2>&1 &"
sleep 30  # Increased wait time for proxy to start
if [ ! -f /tmp/dashboard_url.txt ]; then
    log "Failed to start Minikube dashboard proxy."
    exit 1
fi
DASHBOARD_URL=$(head -n 1 /tmp/dashboard_url.txt)
if [ -z "$DASHBOARD_URL" ]; then
    log "Failed to retrieve dashboard URL."
    exit 1
fi
log "Local Dashboard URL: $DASHBOARD_URL"
SERVER_IP=$(hostname -I | awk '{print $1}')
DASHBOARD_URL_LAN=$(echo "$DASHBOARD_URL" | sed "s/127\.0\.0\.1/$SERVER_IP/")
PORT=$(echo "$DASHBOARD_URL" | sed 's/.*://' | sed 's/\/.*//')
log "LAN Dashboard URL: $DASHBOARD_URL_LAN"
log "The dashboard is exposed on port $PORT. Ensure your firewall allows incoming connections on this port from your LAN."

# Test dashboard access locally
log "Testing dashboard access locally..."
if curl --max-time 10 -s "$DASHBOARD_URL" | grep -q "Kubernetes Dashboard"; then
    log "Dashboard is accessible locally."
else
    log "Failed to access dashboard locally."
    exit 1
fi

# Verify installation
log "Verifying installation..."
log_command "minikube status"
check_success $? "Checking Minikube status"
log_command "kubectl cluster-info"
check_success $? "Checking cluster info"

# Completion message
log "=== Installation Complete ==="
log "Minikube, kubectl, and dashboard installed successfully."
log "Log file: $LOGFILE"
log "To access the dashboard from your LAN, use: $DASHBOARD_URL_LAN"
log "For issues, review $LOGFILE and Minikube documentation."