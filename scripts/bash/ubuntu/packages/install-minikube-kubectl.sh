#!/bin/bash

# Determine the original non-root user
if [ -n "$SUDO_USER" ]; then
    ORIGINAL_USER="$SUDO_USER"
else
    ORIGINAL_USER="$USER"
fi

# Log file setup
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/minikube_install_${TIMESTAMP}.log"

log() {
    echo "[$(date +%Y-%m-%d\ %H:%M:%S)] $1" | tee -a "$LOG_FILE"
}

check_status() {
    if [ $? -ne 0 ]; then
        log "ERROR: $1 failed"
        exit 1
    fi
}

# Create log file
log "Creating log file at $LOG_FILE"
touch "$LOG_FILE"
check_status "Creating log file"

# Detect server details
log "Detecting local server details"
HOSTNAME=$(hostname -f)
log "Using $HOSTNAME for Kubernetes API"

# Check /etc/hosts
log "Checking /etc/hosts for $HOSTNAME"
if ! grep -q "$HOSTNAME" /etc/hosts; then
    log "Adding $HOSTNAME to /etc/hosts"
    echo "127.0.0.1 $HOSTNAME" | sudo tee -a /etc/hosts
    check_status "Updating /etc/hosts"
else
    log "$HOSTNAME already configured in /etc/hosts"
fi

# Check sudo privileges
log "Checking sudo privileges"
sudo -n true 2>/dev/null
check_status "Verifying sudo privileges"

# Check Docker group membership
log "Checking Docker group membership"
if ! groups "$ORIGINAL_USER" | grep -q docker; then
    log "Adding user $ORIGINAL_USER to docker group"
    sudo usermod -aG docker "$ORIGINAL_USER"
    check_status "Adding user to docker group"
    log "WARNING: You have been added to the docker group. Please log out and back in, then re-run this script."
    log "Alternatively, run: sg docker -c './$0'"
    exit 1
else
    log "User is in docker group"
fi

# Verify Docker access
log "Verifying Docker access"
sudo -u "$ORIGINAL_USER" docker ps >/dev/null 2>&1
check_status "Docker access verification"

# Calculate bridge IP
log "Calculated bridge IP: 172.18.0.1/16"
if ip addr show | grep -q "172.18.0.1"; then
    log "ERROR: IP 172.18.0.1/16 conflicts with existing interface"
    exit 1
else
    log "No conflicts found for IP 172.18.0.1/16"
fi

# Install kubectl
TEMP_DIR=$(mktemp -d)
log "Installing kubectl"
curl -Lo "$TEMP_DIR/kubectl" "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
check_status "Downloading kubectl"
chmod +x "$TEMP_DIR/kubectl"
sudo install -o root -g root -m 0755 "$TEMP_DIR/kubectl" /usr/local/bin/kubectl
check_status "Installing kubectl"
log "kubectl installed successfully"

# Install Minikube
log "Installing Minikube"
curl -Lo "$TEMP_DIR/minikube" https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
check_status "Downloading Minikube"
chmod +x "$TEMP_DIR/minikube"
sudo install -o root -g root -m 0755 "$TEMP_DIR/minikube" /usr/local/bin/minikube
check_status "Installing Minikube"
log "Minikube installed successfully"

# Start Minikube as the original user
DOCKER_NETWORK="bridge"
log "Starting Minikube"
sudo -u "$ORIGINAL_USER" minikube start --driver=docker --network="$DOCKER_NETWORK" --apiserver-ips=192.168.4.110 --apiserver-port=8443 || {
    log "ERROR: Failed to start Minikube"
    exit 1
}

# Configure kubeconfig as the original user
log "Configuring kubeconfig"
sudo -u "$ORIGINAL_USER" minikube update-context
sudo -u "$ORIGINAL_USER" kubectl config use-context minikube

# Verify API server connectivity
log "Verifying Kubernetes API server"
sudo -u "$ORIGINAL_USER" kubectl cluster-info || {
    log "ERROR: Failed to connect to Kubernetes API"
    exit 1
}

# Deploy Portainer agent
log "Deploying Portainer agent"
sudo -u "$ORIGINAL_USER" kubectl apply -f https://raw.githubusercontent.com/portainer/k8s/master/deploy/manifests/portainer/portainer-agent-k8s.yaml -n portainer || {
    log "ERROR: Failed to deploy Portainer agent"
    exit 1
}

# Run diagnostic tests
log "Running diagnostic tests"
sudo -u "$ORIGINAL_USER" kubectl get nodes | tee -a "$LOG_FILE"
sudo -u "$ORIGINAL_USER" kubectl get pods -n portainer | tee -a "$LOG_FILE"

log "Minikube and kubectl installation completed successfully"