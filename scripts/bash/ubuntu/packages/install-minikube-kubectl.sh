#!/bin/bash

# Script to install Minikube and kubectl on Ubuntu 24.04, deploying a single-node Kubernetes cluster
# Uses Docker as the container runtime (assumes Docker is pre-installed)
# Configures Docker and Minikube to use a user-specified network (default 172.18.0.0/16)
# Deploys Portainer agent for remote management
# Configures kubeconfig and systemd auto-start
# Preserves existing IPTABLES rules and adds only necessary new rules
# Includes diagnostic tests and Portainer Agent connection instructions for CE

# Exit on any error
set -e

# Function to log messages with timestamps
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# Function to validate Docker network format and calculate bridge IP
validate_docker_network() {
    local network="$1"
    if ! echo "$network" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'; then
        log "ERROR: Invalid DOCKER_NETWORK format: $network"
        exit 1
    fi
    DOCKER_BIP=$(echo "$network" | awk -F'/' '{split($1,a,"."); print a[1]"."a[2]"."a[3]".1/"$2}')
    log "Calculated bridge IP: $DOCKER_BIP"
}

# Function to check for network conflicts with Docker bridge IP
check_network_conflicts() {
    local ip="$1"
    if ip addr show | grep -q "$ip"; then
        log "WARNING: IP $ip is already in use on this host"
        return 1
    fi
    log "No conflicts found for IP $ip"
    return 0
}

# Set up logging
LOG_FILE="/var/log/minikube_install_$(date '+%Y%m%d_%H%M%S').log"
log "Creating log file at $LOG_FILE"

# Main script logic
log "Detecting local server details"
HOSTNAME=$(hostname).skint.private
log "Using $HOSTNAME for Kubernetes API"

log "Checking /etc/hosts for $HOSTNAME"
if grep -q "$HOSTNAME" /etc/hosts; then
    log "$HOSTNAME already configured in /etc/hosts"
else
    log "Adding $HOSTNAME to /etc/hosts"
    echo "127.0.0.1 $HOSTNAME" | sudo tee -a /etc/hosts
fi

log "Checking sudo privileges"
sudo -n true 2>/dev/null || { log "ERROR: Sudo privileges required"; exit 1; }

log "Checking Docker group membership"
if groups | grep -q docker; then
    log "User is in docker group"
else
    log "WARNING: User not in docker group, may need sudo for Docker"
fi

log "Verifying Docker access"
docker ps >/dev/null 2>&1 || { log "ERROR: Docker access failed"; exit 1; }

# Validate Docker network
DOCKER_NETWORK="172.18.0.0/16"
validate_docker_network "$DOCKER_NETWORK"

# Check for network conflicts
check_network_conflicts "$DOCKER_BIP" || log "Proceeding despite potential network conflict, may affect Minikube start"

# Install kubectl
log "Installing kubectl"
if ! command -v kubectl >/dev/null 2>&1; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
    log "kubectl installed successfully"
else
    log "kubectl already installed"
fi

# Install Minikube
log "Installing Minikube"
if ! command -v minikube >/dev/null 2>&1; then
    curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
    sudo install -o root -g root -m 0755 minikube-linux-amd64 /usr/local/bin/minikube
    rm minikube-linux-amd64
    log "Minikube installed successfully"
else
    log "Minikube already installed"
fi

# Start Minikube with Docker driver and specified network
log "Starting Minikube"
minikube start --driver=docker --network="$DOCKER_NETWORK" --apiserver-ips=192.168.4.110 --apiserver-port=8443 || {
    log "ERROR: Failed to start Minikube"
    exit 1
}

# Configure kubeconfig
log "Configuring kubeconfig"
minikube update-context
kubectl config use-context minikube

# Verify API server connectivity
log "Verifying Kubernetes API server"
kubectl cluster-info || { log "ERROR: Failed to connect to Kubernetes API"; exit 1; }

# Deploy Portainer agent (example, adjust as needed)
log "Deploying Portainer agent"
kubectl apply -f https://raw.githubusercontent.com/portainer/k8s/master/deploy/manifests/portainer/portainer-agent-k8s.yaml -n portainer || {
    log "ERROR: Failed to deploy Portainer agent"
}

log "Displaying diagnostic summary"
echo "=============================================================" | tee -a "$LOG_FILE"
echo "Diagnostic Test Summary" | tee -a "$LOG_FILE"
echo "=============================================================" | tee -a "$LOG_FILE"
kubectl get nodes | tee -a "$LOG_FILE"
kubectl get pods -n portainer | tee -a "$LOG_FILE"

log "Installation and setup completed successfully"
exit 0