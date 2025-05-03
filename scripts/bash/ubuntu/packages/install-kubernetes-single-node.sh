#!/bin/bash

# Script to deploy a single-node Kubernetes cluster on Ubuntu 24.04
# Uses Kubeadm for cluster setup, Docker as container runtime
# Prepares cluster for management in Portainer (assumes Portainer and Docker are already installed)
# Uses the latest Kubernetes version dynamically
# Requires sudo privileges
# Logs to file and screen with verbose output
# Adds IPTABLES rules without deleting existing ones

# Exit on any error
set -e

# Define log file and variables
LOG_FILE="/var/log/kubernetes_install_$(date +%Y%m%d_%H%M%S).log"
KUBECONFIG_PATH="/etc/kubernetes/admin.conf"
KUBERNETES_PORT="6443"  # Kubernetes API port

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

# Create log file and ensure it's writable
log "Creating log file at $LOG_FILE"
sudo touch "$LOG_FILE"
sudo chmod 664 "$LOG_FILE"
check_status "Creating log file"

# Update system and install prerequisites
log "Updating system and installing prerequisites"
sudo apt update -y 2>/dev/null | tee -a "$LOG_FILE"
sudo apt upgrade -y 2>/dev/null | tee -a "$LOG_FILE"
sudo apt install -y curl apt-transport-https ca-certificates gpg | tee -a "$LOG_FILE"
check_status "Installing prerequisites"

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

# Add user to docker group (if not already added)
log "Adding user $USER to docker group"
sudo usermod -aG docker "$USER" | tee -a "$LOG_FILE"
check_status "Adding user to docker group"

# Get the latest Kubernetes version
log "Fetching the latest Kubernetes version"
KUBERNETES_VERSION=$(curl -s https://api.github.com/repos/kubernetes/kubernetes/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/^v//')
if [ -z "$KUBERNETES_VERSION" ]; then
    log "ERROR: Failed to fetch latest Kubernetes version"
    exit 1
fi
KUBERNETES_MAJOR_MINOR=$(echo "$KUBERNETES_VERSION" | cut -d. -f1,2)
log "Latest Kubernetes version is $KUBERNETES_VERSION (using v$KUBERNETES_MAJOR_MINOR for repository)"

# Install Kubernetes components (kubeadm, kubelet, kubectl)
log "Installing Kubernetes components (version $KUBERNETES_VERSION)"
sudo mkdir -p /etc/apt/keyrings
if ! curl -fsSL "https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_MAJOR_MINOR/deb/Release.key" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg; then
    log "ERROR: Failed to fetch Kubernetes repository key. Retrying with alternative method..."
    curl -fsSL "https://packages.cloud.google.com/apt/doc/apt-key.gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    check_status "Fetching Kubernetes repository key (alternative)"
fi
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_MAJOR_MINOR/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update -y 2>/dev/null | tee -a "$LOG_FILE"
sudo apt install -y kubeadm kubelet kubectl | tee -a "$LOG_FILE"
sudo apt-mark hold kubeadm kubelet kubectl | tee -a "$LOG_FILE"
check_status "Installing Kubernetes components"

# Initialize Kubernetes cluster with Kubeadm
log "Initializing single-node Kubernetes cluster with Docker runtime"
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 | tee -a "$LOG_FILE"
check_status "Initializing Kubernetes cluster"

# Set up kubeconfig for user
log "Setting up kubeconfig"
mkdir -p "$HOME/.kube"
sudo cp -i "$KUBECONFIG_PATH" "$HOME/.kube/config"
sudo chown $(id -u):$(id -g) "$HOME/.kube/config"
check_status "Setting up kubeconfig"

# Allow scheduling on control plane node
log "Removing taint to allow scheduling on control plane node"
kubectl taint nodes --all node-role.kubernetes.io/control-plane- | tee -a "$LOG_FILE"
check_status "Removing control plane taint"

# Install Flannel CNI for networking
log "Installing Flannel CNI"
kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml | tee -a "$LOG_FILE"
check_status "Installing Flannel CNI"

# Wait for Kubernetes nodes to be ready
log "Waiting for Kubernetes nodes to be ready"
timeout 5m bash -c "until kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type==\"Ready\")].status}' | grep -q True; do sleep 5; log 'Waiting for nodes...'; done" | tee -a "$LOG_FILE"
check_status "Waiting for Kubernetes nodes"

# Configure IPTABLES rules (append to existing rules)
log "Configuring IPTABLES rules for Kubernetes"
sudo iptables -A INPUT -p tcp --dport "$KUBERNETES_PORT" -j ACCEPT -m comment --comment "Kubernetes API" | tee -a "$LOG_FILE"
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
log "4. Upload or copy the kubeconfig from $HOME/.kube/config"
log "5. Save and connect to manage the cluster"

# Display completion instructions
SERVER_IP=$(ip -4 addr show | grep inet | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
log "Kubernetes cluster installation completed successfully!"
log "Verify cluster status with: kubectl cluster-info"
log "Check nodes with: kubectl get nodes"
log "Log file: $LOG_FILE"

# Ensure log file is readable
sudo chmod 664 "$LOG_FILE"