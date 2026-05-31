#!/bin/bash

# Variables
LOG_DIR="/logs"
LOG_FILE="$LOG_DIR/install_master_$(date +%Y%m%d%H%M%S).log"
LOAD_BALANCER_DNS=""
LOAD_BALANCER_PORT=""
POD_NETWORK_CIDR="192.168.0.0/16"

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

# Master setup
master_setup() {
  log "Initializing Kubernetes master node..."
  sudo kubeadm init --control-plane-endpoint "${LOAD_BALANCER_DNS}:${LOAD_BALANCER_PORT}" --pod-network-cidr=${POD_NETWORK_CIDR} --upload-certs | tee -a $LOG_FILE

  log "Setting up kubeconfig..."
  mkdir -p $HOME/.kube | tee -a $LOG_FILE
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config | tee -a $LOG_FILE
  sudo chown $(id -u):$(id -g) $HOME/.kube/config | tee -a $LOG_FILE

  log "Deploying Calico network..."
  kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml | tee -a $LOG_FILE
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
if [ -f "/etc/kubernetes/admin.conf" ]; then
  log "Kubernetes master node already initialized. Upgrading components..."
  upgrade_components
else
  log "Setting up Kubernetes master node..."
  read -p "Enter the Load Balancer DNS: " LOAD_BALANCER_DNS
  read -p "Enter the Load Balancer Port: " LOAD_BALANCER_PORT
  common_setup
  master_setup
fi

log "Master node setup completed."
