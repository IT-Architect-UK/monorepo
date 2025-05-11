#!/bin/bash

# Define log file
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

# Check sudo privileges
sudo -v
if [ $? -ne 0 ]; then
    log "Failed to obtain sudo privileges. Exiting."
    exit 1
fi

# Check write permissions for /tmp
log "Checking write permissions for /tmp..."
if ! touch /tmp/test_write 2>/dev/null; then
    log "Cannot write to /tmp. Check permissions."
    exit 1
fi
rm -f /tmp/test_write
log "Write permissions for /tmp confirmed."

# Install Docker if not present
if ! command_exists docker; then
    log "Installing Docker..."
    log_command "sudo apt update"
    check_success $? "apt update"
    log_command "sudo apt install -y apt-transport-https ca-certificates curl software-properties-common"
    check_success $? "Installing dependencies"
    log_command "sudo install -m 0755 -d /etc/apt/keyrings"
    check_success $? "Creating keyrings directory"
    log_command "sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc"
    check_success $? "Downloading Docker GPG key"
    log_command "sudo chmod a+r /etc/apt/keyrings/docker.asc"
    check_success $? "Setting permissions for Docker GPG key"
    log_command "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null"
    check_success $? "Adding Docker repository"
    log_command "sudo apt update"
    check_success $? "apt update after adding Docker repository"
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

# Install kubectl if not present
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

# Install minikube if not present
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

# Wait for dashboard pod to be created
log "Waiting for dashboard pod to be created..."
for i in {1..60}; do
    POD_NAME=$(kubectl get pod -n kubernetes-dashboard -l k8s-app=kubernetes-dashboard -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -n "$POD_NAME" ]; then
        break
    fi
    log "No dashboard pod found yet. Waiting..."
    sleep 5
done
if [ -z "$POD_NAME" ]; then
    log "No dashboard pod found after 5 minutes."
    log "Checking all pods in namespace:"
    log_command "kubectl get pods -n kubernetes-dashboard --show-labels"
    log "Please check Minikube logs with 'minikube logs' for errors."
    exit 1
fi
log "Dashboard pod found: $POD_NAME"

# Wait for dashboard pod to be ready
log "Waiting for dashboard pod to be ready..."
log_command "kubectl wait --for=condition=ready pod/$POD_NAME -n kubernetes-dashboard --timeout=300s"
check_success $? "Waiting for dashboard pod"

# Check if pod is running
POD_STATUS=$(kubectl get pod/$POD_NAME -n kubernetes-dashboard -o jsonpath='{.status.phase}' 2>/dev/null)
if [ "$POD_STATUS" != "Running" ]; then
    log "Dashboard pod is not running. Status: $POD_STATUS"
    exit 1
fi

# Get container port
CONTAINER_PORT=$(kubectl get pod/$POD_NAME -n kubernetes-dashboard -o jsonpath='{.spec.containers[0].ports[0].containerPort}' 2>/dev/null)
if [ -z "$CONTAINER_PORT" ]; then
    log "Failed to get container port for dashboard pod. Defaulting to 9090."
    CONTAINER_PORT=9090
fi
log "Dashboard container port: $CONTAINER_PORT"

# Choose a local port, e.g., 8001
LOCAL_PORT=8001

# Start port-forward
log "Starting port-forward for dashboard LAN access on port $LOCAL_PORT..."
log_command "kubectl port-forward --address 0.0.0.0 pods/$POD_NAME $LOCAL_PORT:$CONTAINER_PORT -n kubernetes-dashboard > /tmp/port-forward.log 2>&1 &"
sleep 45  # Increased wait time for proxy to start
if ! pgrep -f "kubectl port-forward" > /dev/null; then
    log "Port-forward process did not start. Check /tmp/port-forward.log for errors."
    exit 1
fi
if ! ss -tuln | grep -q ":$LOCAL_PORT "; then
    log "Port $LOCAL_PORT is not listening. Check /tmp/port-forward.log for errors."
    exit 1
fi

# Test dashboard access locally
log "Testing dashboard access locally..."
if curl --max-time 90 -s "[invalid url, do not cite] | grep -q "Kubernetes Dashboard"; then
    log "Dashboard is accessible locally."
    SERVER_IP=$(hostname -I | awk '{print $1}')
    DASHBOARD_URL="[invalid url, do not cite]
    log "To access the dashboard from your LAN, use: $DASHBOARD_URL"
else
    log "Failed to access dashboard locally. Check if port-forward is running and dashboard is enabled."
    exit 1
fi

# Verify installation
log "Verifying installation..."
log_command "minikube status"
check_success $? "Checking Minikube status"
log_command "kubectl cluster-info"
check_success $? "Checking cluster info"

# Completion message and summary
log "=== Script Completion Summary ==="
log "Minikube Status: $(minikube status | grep -E 'host|kubelet|apiserver' || echo 'Status unavailable')"
log "kubectl Version: $(kubectl version --client --output=yaml | grep gitVersion || echo 'Version unavailable')"
log "Kubernetes Dashboard: Accessible at $DASHBOARD_URL"
log "Remote Management: Copy ~/.kube/config to your local machine, set KUBECONFIG=~/.kube/config, and use 'kubectl' commands."
log "Log file: $LOGFILE"
log "To stop the dashboard access, run: pkill -f 'kubectl port-forward'"
log "For issues, review $LOGFILE and Minikube logs with 'minikube logs'."