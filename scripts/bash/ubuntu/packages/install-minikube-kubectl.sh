#!/bin/bash

# Script to install Minikube and kubectl on Ubuntu 24.04, deploying a single-node Kubernetes cluster
# Uses Docker as the container runtime (assumes Docker and Portainer agent are pre-installed)
# Prepares cluster for management in Portainer
# Includes verbose logging, error handling, and IPTABLES rules (appended without deleting existing ones)
# Requires sudo privileges

# Exit on any error
set -e

# Define log file and variables
LOG_FILE="/var/log/minikube_install_$(date +%Y%m%d_%H%M%S).log"
MINIKUBE_MEMORY="4096"  # 4GB RAM
MINIKUBE_CPUS="2"      # 2 CPUs
MINIKUBE_DISK="20g"    # 20GB disk
KUBERNETES_PORT="8443" # Minikube Kubernetes API port

# Function to log messages to file and screen
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | tee -a "$LOG_FILE"
}

# Function to check if a command succeeded
check_status() {
    if [ $? -ne 0 ]; then
        log "ERROR: $1 failed"
        exit 1
    fi
}

# Introduction summary
log "===== Introduction Summary ====="
log "This script deploys a single-node Kubernetes cluster on Ubuntu 24.04 using Minikube."
log "It performs the following steps:"
log "1. Verifies pre-installed Docker and configures user permissions."
log "2. Installs Minikube and kubectl."
log "3. Starts Minikube with the Docker driver and enables the ingress addon."
log "4. Configures IPTABLES rules for Kubernetes and Docker."
log "5. Prepares kubeconfig for Portainer management."
log "Prerequisites:"
log "- Docker and Portainer agent must be pre-installed."
log "- Sudo privileges are required."
log "- Minimum 4GB RAM, 2 CPUs, 20GB disk."
log "Logs are saved to $LOG_FILE."
log "================================"

# Create log file and ensure it's writable
log "Creating log file at $LOG_FILE"
sudo touch "$LOG_FILE"
sudo chmod 664 "$LOG_FILE"
check_status "Creating log file"

# Verify Docker is installed and running
log "Verifying Docker installation"
if ! command -v docker &> /dev/null; then
    log "ERROR: Docker is not installed. Please install Docker before running this script."
    exit 1
fi
sudo systemctl enable docker | tee -a "$LOG_FILE"
sudo systemctl start docker | tee -a "$LOG_FILE"
check_status "Verifying Docker"

# Verify Docker CRI compatibility
log "Verifying Docker CRI compatibility"
if ! docker info --format '{{.CgroupDriver}}' | grep -q "systemd"; then
    log "Configuring Docker to use systemd cgroup driver"
    sudo mkdir -p /etc/docker
    echo '{"exec-opts": ["native.cgroupdriver=systemd"]}' | sudo tee /etc/docker/daemon.json > /dev/null
    sudo systemctl restart docker
    check_status "Configuring Docker cgroup driver"
fi

# Add user to docker group and refresh group membership
log "Adding user $USER to docker group"
sudo usermod -aG docker "$USER" | tee -a "$LOG_FILE"
check_status "Adding user to docker group"
log "Refreshing group membership"
newgrp docker << EOF
exit
EOF
check_status "Refreshing group membership"

# Install Minikube
log "Installing Minikube"
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 | tee -a "$LOG_FILE"
sudo install minikube-linux-amd64 /usr/local/bin/minikube | tee -a "$LOG_FILE"
check_status "Installing Minikube"
rm minikube-linux-amd64

# Install kubectl
log "Installing kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" | tee -a "$LOG_FILE"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl | tee -a "$LOG_FILE"
check_status "Installing kubectl"
rm kubectl

# Start Minikube
log "Starting Minikube with Docker driver, $MINIKUBE_MEMORY MB RAM, $MINIKUBE_CPUS CPUs, and $MINIKUBE_DISK disk"
minikube start --driver=docker --addons=ingress --cpus="$MINIKUBE_CPUS" --memory="$MINIKUBE_MEMORY" --disk-size="$MINIKUBE_DISK" --wait=false | tee -a "$LOG_FILE"
check_status "Starting Minikube"

# Verify Minikube status
log "Verifying Minikube status"
minikube status | tee -a "$LOG_FILE"
check_status "Verifying Minikube status"

# Wait for Kubernetes nodes to be ready
log "Waiting for Kubernetes nodes to be ready"
timeout 5m bash -c "until kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type==\"Ready\")].status}' | grep -q True; do sleep 5; log 'Waiting for nodes...'; done" | tee -a "$LOG_FILE"
check_status "Waiting for Kubernetes nodes"

# Configure IPTABLES rules (append to existing rules)
log "Configuring IPTABLES rules for Kubernetes"
sudo iptables -A INPUT -p tcp --dport "$KUBERNETES_PORT" -j ACCEPT -m comment --comment "Minikube Kubernetes API" | tee -a "$LOG_FILE"
sudo iptables -A INPUT -i docker0 -j ACCEPT -m comment --comment "Docker interface" | tee -a "$LOG_FILE"
check_status "Configuring IPTABLES rules"

# Save IPTABLES rules
log "Saving IPTABLES rules"
sudo iptables-save > /etc/iptables/rules.v4 | tee -a "$LOG_FILE"
check_status "Saving IPTABLES rules"

# Instructions for Portainer integration
log "Preparing kubeconfig for Portainer integration"
log "To manage the Kubernetes cluster in Portainer:"
log "1. Access Portainer UI (e.g., http://$SERVER_IP:9000)"
log "2. Go to 'Environments' > 'Add Environment' > 'Kubernetes'"
log "3. Select 'Local Kubernetes' or 'Import kubeconfig'"
log "4. Upload or copy the kubeconfig from $HOME/.kube/config (created by Minikube)"
log "5. Save and connect to manage the cluster"

# Display completion instructions
SERVER_IP=$(ip -4 addr show | grep inet | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
log "Kubernetes cluster installation completed successfully!"
log "Verify cluster status with: kubectl cluster-info"
log "Check nodes with: kubectl get nodes"
log "Log file: $LOG_FILE"

# Ensure log file is readable
sudo chmod 664 "$LOG_FILE"