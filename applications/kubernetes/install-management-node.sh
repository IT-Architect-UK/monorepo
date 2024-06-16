#!/bin/bash

# Variables
LOG_DIR="/logs"
LOG_FILE="$LOG_DIR/install_management_$(date +%Y%m%d%H%M%S).log"
RANCHER_HOSTNAME=""

# Create log directory if it doesn't exist
mkdir -p $LOG_DIR

# Function to log messages
log() {
  echo "$1" | tee -a $LOG_FILE
}

# Function to install Docker
install_docker() {
  log "Updating system packages..."
  sudo apt-get update | tee -a $LOG_FILE
  log "Installing Docker..."
  sudo apt-get install -y docker.io | tee -a $LOG_FILE
  log "Starting Docker service..."
  sudo systemctl enable docker | tee -a $LOG_FILE
  sudo systemctl start docker | tee -a $LOG_FILE
}

# Function to install Kubernetes components
install_k8s_components() {
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

# Function to install Helm
install_helm() {
  log "Installing Helm..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash | tee -a $LOG_FILE
}

# Function to deploy Rancher
deploy_rancher() {
  log "Adding Rancher Helm repository..."
  helm repo add rancher-latest https://releases.rancher.com/server-charts/latest | tee -a $LOG_FILE
  helm repo update | tee -a $LOG_FILE
  log "Creating namespace for Rancher..."
  kubectl create namespace cattle-system | tee -a $LOG_FILE
  log "Installing Rancher..."
  helm install rancher rancher-latest/rancher --namespace cattle-system --set hostname=${RANCHER_HOSTNAME} | tee -a $LOG_FILE
  log "Rancher installation completed. Access Rancher at https://${RANCHER_HOSTNAME}"
}

# Main
log "Starting management server setup..."
read -p "Enter the hostname for Rancher (e.g., rancher.yourdomain.com): " RANCHER_HOSTNAME

install_docker
install_k8s_components
install_helm
deploy_rancher

log "Management server setup completed."
