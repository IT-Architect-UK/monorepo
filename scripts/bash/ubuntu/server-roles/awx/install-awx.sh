#!/bin/bash

# This script installs Ansible AWX on a fresh Ubuntu 24.04 LTS instance using Minikube and the AWX Operator.
# It assumes a system with at least 8GB RAM and 4 CPUs (adjust Minikube flags if needed).
# Run as a non-root user with sudo privileges.
# Note: This uses the Docker driver for Minikube; if on bare metal with KVM support, you can change to --driver=kvm2.

set -e  # Exit on error

# Step 1: Update system and install prerequisites
echo "Updating system and installing prerequisites..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y apt-transport-https ca-certificates curl gnupg software-properties-common git make conntrack

# Step 2: Install Docker
echo "Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
newgrp docker  # Reload group membership without logout

# Step 3: Install kubectl
echo "Installing kubectl..."
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -LO "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client

# Step 4: Install Minikube
echo "Installing Minikube..."
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube
minikube version

# Step 5: Start Minikube cluster
echo "Starting Minikube with Docker driver..."
minikube start --driver=docker --addons=ingress --cpus=4 --memory=8192m
minikube status
kubectl get pods -A  # Verify cluster is running

# Step 6: Clone and deploy AWX Operator
echo "Cloning AWX Operator repository..."
git clone https://github.com/ansible/awx-operator.git
cd awx-operator

# Checkout the latest stable release (adjust if a specific version is needed)
LATEST_TAG=$(git describe --tags $(git rev-list --tags --max-count=1))
git checkout ${LATEST_TAG}
echo "Using AWX Operator version: ${LATEST_TAG}"

# Set namespace and deploy operator
export NAMESPACE=awx
make deploy

# Verify operator deployment
kubectl get pods -n ${NAMESPACE}

cd ..

# Step 7: Create AWX deployment YAML
echo "Creating AWX deployment configuration..."
cat <<EOF > awx.yml
---
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx
spec:
  service_type: nodeport
EOF

# Step 8: Deploy AWX
echo "Deploying AWX..."
kubectl apply -f awx.yml -n ${NAMESPACE}

# Step 9: Monitor deployment
echo "Monitoring AWX deployment (this may take 5-10 minutes)..."
kubectl get pods -n ${NAMESPACE} -w  # Run this manually if needed to watch progress

# Step 10: Access instructions (run these after pods are ready)
echo "Installation complete. To access AWX:"
echo "1. Get the NodePort service details: kubectl get svc -n ${NAMESPACE}"
echo "2. For local access, get URL: minikube service awx-service --url -n ${NAMESPACE}"
echo "3. For external access (e.g., from host machine), port-forward:"
echo "   kubectl port-forward svc/awx-service --address 0.0.0.0 8080:80 -n ${NAMESPACE} &"
echo "   Then access at http://<your-ubuntu-ip>:8080"
echo "4. Default username: admin"
echo "5. Get password: kubectl get secret awx-admin-password -o jsonpath='{.data.password}' -n ${NAMESPACE} | base64 --decode; echo"

# Notes:
# - If Minikube fails with Docker driver, ensure nested virtualization is enabled if on a VM, or switch to --driver=none (requires root).
# - For production, use a full Kubernetes cluster instead of Minikube.
# - Check logs if issues: kubectl logs -f deployments/awx-operator-controller-manager -c awx-manager -n ${NAMESPACE}