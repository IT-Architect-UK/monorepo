#!/bin/bash

# Variables
LOG_DIR="/logs"
LOG_FILE="$LOG_DIR/install_worker_$(date +%Y%m%d%H%M%S).log"
JOIN_COMMAND=""

# Create log directory if it doesn't exist
mkdir -p $LOG_DIR

# Function to log messages
log() {
  echo "$1" | tee -a $LOG_FILE
}

# Common setup
common_setup() {
  log "Updating system packages..."
  sudo apt-get update | tee -a $LOG_FILE
  log "Installing Docker..."
  sudo apt-get install -y docker.io | tee -a $LOG_FILE
  log "Starting Docker service..."
  sudo systemctl enable docker | tee -a $LOG_FILE
  sudo systemctl start docker | tee -a $LOG_FILE
  log "Adding Kubernetes APT key..."
  sudo curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - | tee -a $LOG_FILE
  log "Adding Kubernetes APT repository..."
  echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list | tee -a $LOG_FILE
  log "Updating package list..."
  sudo apt-get update | tee -a $LOG_FILE
  log "Installing Kubernetes components..."
  sudo apt-get install -y kubelet kubeadm kubectl | tee -a $LOG_FILE
  sudo apt-mark hold kubelet kubeadm kubectl | tee -a $LOG_FILE
}

# Worker setup
worker_setup() {
  log "Joining the Kubernetes cluster..."
  eval sudo $JOIN_COMMAND | tee -a $LOG_FILE
}

# Upgrade components
upgrade_components() {
  log "Upgrading system packages..."
  sudo apt-get update | tee -a $LOG_FILE
  log "Upgrading Docker..."
  sudo apt-get install --only-upgrade -y docker.io | tee -a $LOG_FILE
  log "Upgrading Kubernetes components..."
  sudo apt-get install --only-upgrade -y kubelet kubeadm kubectl | tee -a $LOG_FILE
}

# Main
if [ -f "/var/lib/kubelet/config.yaml" ]; then
  log "Kubernetes worker node already joined. Upgrading components..."
  upgrade_components
else
  log "Setting up Kubernetes worker node..."
  read -p "Enter the Kubernetes join command: " JOIN_COMMAND
  common_setup
  worker_setup
fi

log "Worker node setup completed."
