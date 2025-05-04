#!/bin/bash

# Script to install the latest Ansible AWX on Ubuntu 24.04 using Minikube
# Assumes Docker (with Compose), Minikube, kubectl, and Portainer agent are pre-installed
# Runs from SSH session or local console, prompts for sudo password when required
# Includes prerequisite checks, error handling, and verbose logging to file and screen
# Appends IPTABLES rules without deleting existing ones
# Prepares AWX for management in Portainer
# Must be run as a non-root user with sudo privileges

# Exit on any error
set -e

# Define log file and variables
LOG_FILE="/var/log/awx_install_$(date +%Y%m%d_%H%M%S).log"
AWX_NAMESPACE="ansible-awx"
AWX_PORT="30445"       # NodePort for AWX access (30000-32767 range)
KUBERNETES_PORT="8443" # Minikube Kubernetes API port
MINIKUBE_MEMORY="8192" # 8GB RAM
MINIKUBE_CPUS="4"      # 4 CPUs
MINIKUBE_DISK="50g"    # 50GB disk
NON_ROOT_USER="$USER"  # Store the invoking user
TEMP_DIR="/tmp"        # Temporary directory for downloads

# Function to log messages to file and screen
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | sudo tee -a "$LOG_FILE"
}

# Function to check if a command succeeded
check_status() {
    if [ $? -ne 0 ]; then
        log "ERROR: $1 failed"
        exit 1
    fi
}

# Check if running as root
if [ "$(id -u)" -eq 0 ]; then
    log "ERROR: This script must not be run as root. Run as a non-root user (e.g., pos-admin) with sudo privileges."
    log "Example: ./install_awx_ubuntu24.sh"
    log "Alternatively, modify the script to use 'minikube start --force' if root execution is required."
    exit 1
fi

# Check if sudo privileges are available
log "Checking sudo privileges"
if ! sudo -n true 2>/dev/null; then
    log "ERROR: User $NON_ROOT_USER does not have sudo privileges. Please grant sudo access and try again."
    exit 1
fi

# Introduction summary
log "===== Introduction Summary ====="
log "This script installs the latest Ansible AWX on Ubuntu 24.04 using Minikube."
log "It performs the following steps:"
log "1. Verifies pre-installed Docker, Minikube, kubectl, and Portainer agent."
log "2. Ensures Minikube is running with the Docker driver and ingress addon."
log "3. Installs kustomize and the latest AWX Operator."
log "4. Deploys AWX with a NodePort service."
log "5. Configures IPTABLES rules for AWX and Kubernetes."
log "6. Prepares kubeconfig for Portainer management."
log "Prerequisites:"
log "- Docker (with Compose), Minikube, kubectl, and Portainer agent must be pre-installed."
log "- Run as a non-root user with sudo privileges (sudo will be prompted for specific commands)."
log "- Minimum 8GB RAM, 4 CPUs, 50GB disk."
log "Logs are saved to $LOG_FILE."
log "================================"

# Create log file and ensure it's writable
log "Creating log file at $LOG_FILE"
sudo touch "$LOG_FILE"
sudo chmod 664 "$LOG_FILE"
check_status "Creating log file"

# Prerequisite checks
log "Checking prerequisites"

# Check Docker
if ! command -v docker &> /dev/null; then
    log "ERROR: Docker is not installed. Please install Docker before running this script."
    exit 1
fi
sudo systemctl is-active --quiet docker || {
    log "ERROR: Docker service is not running. Starting Docker..."
    sudo systemctl start docker
    check_status "Starting Docker"
}
log "Docker is installed and running"

# Check Docker group membership
if ! groups | grep -q docker; then
    log "ERROR: User $NON_ROOT_USER is not in the docker group."
    log "Run: sudo usermod -aG docker $NON_ROOT_USER, then log out and back in."
    log "Alternatively, run: sg docker -c './install_awx_ubuntu24.sh'"
    exit 1
fi
if ! docker info &> /dev/null; then
    log "ERROR: User $NON_ROOT_USER cannot access Docker daemon. Ensure you have logged out/in after adding to docker group."
    log "Run: sg docker -c './install_awx_ubuntu24.sh' or log out and back in."
    exit 1
fi
log "Docker group membership verified"

# Check Docker Compose
if ! command -v docker-compose &> /dev/null; then
    log "ERROR: Docker Compose is not installed. Please install Docker Compose before running this script."
    exit 1
fi
log "Docker Compose is installed"

# Check Minikube
if ! command -v minikube &> /dev/null; then
    log "ERROR: Minikube is not installed. Please install Minikube before running this script."
    exit 1
fi
log "Minikube is installed"

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    log "ERROR: kubectl is not installed. Please install kubectl before running this script."
    exit 1
fi
log "kubectl is installed"

# Check Portainer agent (basic check for running container)
if ! docker ps | grep -q portainer/portainer-ce; then
    log "WARNING: Portainer agent container not detected. Ensure the Portainer agent is running and configured for Kubernetes."
fi
log "Portainer agent check completed"

# Ensure Minikube is running
log "Checking Minikube status"
if ! minikube status | grep -q "host: Running"; then
    log "Starting Minikube with Docker driver, $MINIKUBE_MEMORY MB, $MINIKUBE_CPUS CPUs, and $MINIKUBE_DISK disk"
    sg docker -c "minikube start --driver=docker --addons=ingress --cpus=$MINIKUBE_CPUS --memory=$MINIKUBE_MEMORY --disk-size=$MINIKUBE_DISK --wait=false" | sudo tee -a "$LOG_FILE"
    check_status "Starting Minikube"
else
    log "Minikube is already running"
fi

# Verify Minikube status
log "Verifying Minikube status"
minikube status | sudo tee -a "$LOG_FILE"
check_status "Verifying Minikube status"

# Wait for Kubernetes nodes to be ready
log "Waiting for Kubernetes nodes to be ready"
timeout 5m bash -c "
    until kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null | grep -q True; do
        sleep 5
        echo \"[$(date '+%Y-%m-%d %H:%M:%S')] Waiting for nodes...\" | sudo tee -a \"$LOG_FILE\"
    done
" || {
    log "ERROR: Kubernetes nodes failed to become ready within 5 minutes"
    exit 1
}
check_status "Waiting for Kubernetes nodes"

# Install kustomize
log "Installing kustomize"
if ! command -v kustomize &> /dev/null; then
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" -o "$TEMP_DIR/install_kustomize.sh" | sudo tee -a "$LOG_FILE"
    check_status "Downloading kustomize installer"
    bash "$TEMP_DIR/install_kustomize.sh" | sudo tee -a "$LOG_FILE"
    check_status "Running kustomize installer"
    sudo mv kustomize /usr/local/bin/ | sudo tee -a "$LOG_FILE"
    check_status "Installing kustomize"
    rm "$TEMP_DIR/install_kustomize.sh"
else
    log "kustomize is already installed"
fi

# Clone AWX Operator repository (latest version)
log "Cloning AWX Operator repository (main branch for latest version)"
if [ -d "awx-operator" ]; then
    rm -rf awx-operator
fi
git clone https://github.com/ansible/awx-operator.git | sudo tee -a "$LOG_FILE"
check_status "Cloning AWX Operator repository"
cd awx-operator

# Create namespace
log "Creating Kubernetes namespace $AWX_NAMESPACE"
kubectl create namespace "$AWX_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - | sudo tee -a "$LOG_FILE"
check_status "Creating namespace"

# Deploy AWX Operator
log "Deploying AWX Operator"
export NAMESPACE="$AWX_NAMESPACE"
make deploy | sudo tee -a "$LOG_FILE"
check_status "Deploying AWX Operator"

# Create AWX demo configuration with NodePort
log "Creating AWX demo configuration"
cat <<EOF > awx-demo.yml
---
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-demo
  namespace: $AWX_NAMESPACE
spec:
  service_type: NodePort
  nodeport_port: $AWX_PORT
  ingress_type: none
  hostname: awx-demo.local
  persistent_volume_claim:
    enabled: true
    storage_class: local-path
    size: 5Gi
EOF
check_status "Creating AWX demo configuration"

# Apply AWX demo configuration
log "Applying AWX demo configuration"
kubectl apply -f awx-demo.yml -n "$AWX_NAMESPACE" | sudo tee -a "$LOG_FILE"
check_status "Applying AWX demo configuration"

# Wait for AWX pods to be ready
log "Waiting for AWX pods to be ready (this may take a few minutes)"
timeout 10m bash -c "
    until kubectl get pods -n $AWX_NAMESPACE -l 'app.kubernetes.io/managed-by=awx-operator' -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q Running; do
        sleep 10
        echo \"[$(date '+%Y-%m-%d %H:%M:%S')] Waiting for AWX pods...\" | sudo tee -a \"$LOG_FILE\"
    done
" || {
    log "ERROR: AWX pods failed to become ready within 10 minutes"
    exit 1
}
check_status "Waiting for AWX pods"

# Verify pod status
log "Verifying AWX pod status"
kubectl get pods -n "$AWX_NAMESPACE" | sudo tee -a "$LOG_FILE"
check_status "Verifying pod status"

# Get AWX admin password
log "Retrieving AWX admin password"
AWX_PASSWORD=$(kubectl get secret awx-demo-admin-password -o jsonpath="{.data.password}" -n "$AWX_NAMESPACE" | base64 --decode)
check_status "Retrieving AWX admin password"

# Configure IPTABLES rules (append to existing rules)
log "Configuring IPTABLES rules for AWX and Kubernetes"
sudo iptables -A INPUT -p tcp --dport "$AWX_PORT" -j ACCEPT -m comment --comment "AWX access port" | sudo tee -a "$LOG_FILE"
sudo iptables -A INPUT -p tcp --dport "$KUBERNETES_PORT" -j ACCEPT -m comment --comment "Minikube Kubernetes API" | sudo tee -a "$LOG_FILE"
sudo iptables -A INPUT -i docker0 -j ACCEPT -m comment --comment "Docker interface" | sudo tee -a "$LOG_FILE"
check_status "Configuring IPTABLES rules"

# Save IPTABLES rules
log "Saving IPTABLES rules"
sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
check_status "Saving IPTABLES rules"

# Instructions for Portainer integration
log "Preparing kubeconfig for Portainer integration"
log "To manage AWX in Portainer:"
log "1. Access Portainer UI (e.g., http://$SERVER_IP:9000)"
log "2. Go to 'Environments' > 'Add Environment' > 'Kubernetes' (if not already added)"
log "3. Upload or copy the kubeconfig from $HOME/.kube/config (created by Minikube)"
log "4. Navigate to the 'ansible-awx' namespace to manage AWX resources"
log "5. Save and connect to manage the cluster"

# Display access instructions
SERVER_IP=$(ip -4 addr show | grep inet | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
log "AWX installation completed successfully!"
log "Access AWX at: http://$SERVER_IP:$AWX_PORT"
log "Username: admin"
log "Password: $AWX_PASSWORD"
log "Verify cluster status with: kubectl cluster-info"
log "Check AWX pods with: kubectl get pods -n $AWX_NAMESPACE"
log "Log file: $LOG_FILE"

# Ensure log file is readable
sudo chmod 664 "$LOG_FILE"