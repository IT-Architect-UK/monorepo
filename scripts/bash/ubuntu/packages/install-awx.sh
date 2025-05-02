#!/bin/bash

# Script to install the latest Ansible AWX on Ubuntu 24.04
# Requires sudo privileges
# Logs to file and screen with verbose output
# Adds IPTABLES rules without deleting existing ones

# Exit on any error
set -e

# Define log file and variables
LOG_FILE="/var/log/awx_install_$(date +%Y%m%d_%H%M%S).log"
AWX_NAMESPACE="ansible-awx"
MINIKUBE_MEMORY="8192"  # 8GB RAM
MINIKUBE_CPUS="4"      # 4 CPUs
MINIKUBE_DISK="50g"    # 50GB disk to avoid space issues
AWX_PORT="10445"       # External port for AWX access

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
sudo apt update -y | tee -a "$LOG_FILE"
sudo apt upgrade -y | tee -a "$LOG_FILE"
sudo apt install -y curl git make docker.io iptables net-tools python3-pip | tee -a "$LOG_FILE"
check_status "Installing prerequisites"

# Enable and start Docker
log "Enabling and starting Docker"
sudo systemctl enable docker | tee -a "$LOG_FILE"
sudo systemctl start docker | tee -a "$LOG_FILE"
check_status "Starting Docker"

# Add user to docker group
log "Adding user $USER to docker group"
sudo usermod -aG docker "$USER" | tee -a "$LOG_FILE"
check_status "Adding user to docker group"

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

# Install kustomize
log "Installing kustomize"
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash | tee -a "$LOG_FILE"
sudo mv kustomize /usr/local/bin/ | tee -a "$LOG_FILE"
check_status "Installing kustomize"

# Configure IPTABLES rules (append to existing rules)
log "Configuring IPTABLES rules for AWX and Minikube"
sudo iptables -A INPUT -p tcp --dport "$AWX_PORT" -j ACCEPT -m comment --comment "AWX access port" | tee -a "$LOG_FILE"
sudo iptables -A INPUT -p tcp --dport 8443 -j ACCEPT -m comment --comment "Minikube Kubernetes API" | tee -a "$LOG_FILE"
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT -m comment --comment "HTTP for AWX" | tee -a "$LOG_FILE"
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT -m comment --comment "HTTPS for AWX" | tee -a "$LOG_FILE"
sudo iptables -A INPUT -i docker0 -j ACCEPT -m comment --comment "Docker interface" | tee -a "$LOG_FILE"
check_status "Configuring IPTABLES rules"

# Save IPTABLES rules
log "Saving IPTABLES rules"
sudo iptables-save > /etc/iptables/rules.v4 | tee -a "$LOG_FILE"
check_status "Saving IPTABLES rules"

# Start Minikube
log "Starting Minikube with $MINIKUBE_MEMORY MB RAM, $MINIKUBE_CPUS CPUs, and $MINIKUBE_DISK disk"
minikube start --vm-driver=docker --addons=ingress --cpus="$MINIKUBE_CPUS" --memory="$MINIKUBE_MEMORY" --disk-size="$MINIKUBE_DISK" --wait=false | tee -a "$LOG_FILE"
check_status "Starting Minikube"

# Verify Minikube status
log "Verifying Minikube status"
minikube status | tee -a "$LOG_FILE"
check_status "Verifying Minikube status"

# Clone AWX Operator repository (latest version)
log "Cloning AWX Operator repository (main branch for latest version)"
git clone https://github.com/ansible/awx-operator.git | tee -a "$LOG_FILE"
cd awx-operator
check_status "Cloning AWX Operator repository"

# Create namespace
log "Creating Kubernetes namespace $AWX_NAMESPACE"
kubectl create namespace "$AWX_NAMESPACE" | tee -a "$LOG_FILE"
check_status "Creating namespace"

# Deploy AWX Operator
log "Deploying AWX Operator"
export NAMESPACE="$AWX_NAMESPACE"
make deploy | tee -a "$LOG_FILE"
check_status "Deploying AWX Operator"

# Create AWX demo configuration
log "Creating AWX demo configuration"
cat <<EOF > awx-demo.yml
---
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-demo
  namespace: $AWX_NAMESPACE
spec:
  service_type: ClusterIP
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
kubectl apply -f awx-demo.yml -n "$AWX_NAMESPACE" | tee -a "$LOG_FILE"
check_status "Applying AWX demo configuration"

# Wait for AWX pods to be ready
log "Waiting for AWX pods to be ready (this may take a few minutes)"
timeout 10m bash -c "until kubectl get pods -n $AWX_NAMESPACE -l 'app.kubernetes.io/managed-by=awx-operator' -o jsonpath='{.items[*].status.phase}' | grep -q Running; do sleep 10; log 'Waiting for AWX pods...'; done" | tee -a "$LOG_FILE"
check_status "Waiting for AWX pods"

# Verify pod status
log "Verifying AWX pod status"
kubectl get pods -n "$AWX_NAMESPACE" | tee -a "$LOG_FILE"
check_status "Verifying pod status"

# Set up port forwarding
log "Setting up port forwarding on port $AWX_PORT"
kubectl port-forward service/awx-demo-service -n "$AWX_NAMESPACE" --address 0.0.0.0 "$AWX_PORT":80 &> /dev/null &
check_status "Setting up port forwarding"
sleep 5  # Allow port-forward to initialize

# Get AWX admin password
log "Retrieving AWX admin password"
AWX_PASSWORD=$(kubectl get secret awx-demo-admin-password -o jsonpath="{.data.password}" -n "$AWX_NAMESPACE" | base64 --decode)
check_status "Retrieving AWX admin password"

# Get server IP
SERVER_IP=$(ip -4 addr show | grep inet | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
check_status "Retrieving server IP"

# Display access instructions
log "AWX installation completed successfully!"
log "Access AWX at: http://$SERVER_IP:$AWX_PORT"
log "Username: admin"
log "Password: $AWX_PASSWORD"
log "Log file: $LOG_FILE"
log "To stop port forwarding, run: kill $(ps aux | grep 'kubectl port-forward' | grep -v grep | awk '{print $2}')"

# Ensure log file is readable
sudo chmod 664 "$LOG_FILE"