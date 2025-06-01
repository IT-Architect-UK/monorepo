#!/bin/bash

# === AWX Installation Script ===
# Purpose: Installs AWX on a Minikube cluster using the AWX Operator.
# Target System: Ubuntu 24.04 with Minikube (Docker driver)
# Resources Allocated: Assumes Minikube is running with 8 CPUs, 16GB RAM
# Requirements:
#   - Sudo privileges
#   - Internet access
#   - Minikube running with kubectl configured
#   - Git installed
# Logs: All actions and statuses will be logged to /logs/install_awx_<timestamp>.log for troubleshooting.
# Note: This script assumes Minikube is already set up and uses the latest AWX Operator version.
# ==============================

# Define variables
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOGFILE="/logs/install_awx_${TIMESTAMP}.log"
NAMESPACE="ansible-awx"
AWX_OPERATOR_VERSION="2.19.1"
WORKDIR="/source-files/github/monorepo/scripts/bash/ubuntu/packages"

# Create /logs directory if it doesn't exist
if [ ! -d /logs ]; then
    sudo mkdir -p /logs
fi

# Function to log messages
log() {
    echo "$@" | sudo tee -a "$LOGFILE"
}

# Function to run commands and log output
log_command() {
    local cmd="$1"
    echo "Executing: $cmd" | sudo tee -a "$LOGFILE"
    output=$(bash -c "$cmd" 2>&1)
    status=$?
    echo "$output" | sudo tee -a "$LOGFILE"
    return $status
}

# Function to check command success
check_success() {
    local status=$1
    local message=$2
    if [ "$status" -eq 0 ]; then
        log "$message succeeded."
    else
        log "$message failed. See $LOGFILE for details."
        exit 1
    fi
}

# Function to check if a command exists
command_exists() {
    command -v "$1" > /dev/null 2>&1
}

# Check sudo privileges
sudo -v
if [ $? -ne 0 ]; then
    log "Failed to obtain sudo privileges. Exiting."
    exit 1
fi

# Check write permissions for /tmp
log "Checking write permissions for /tmp..."
if ! touch /tmp/test_write 2>/dev/null; then
    log "Cannot write to /tmp. Check permissions."
    exit 1
fi
rm -f /tmp/test_write
log "Write permissions for /tmp confirmed."

# Check write permissions for working directory
log "Checking write permissions for $WORKDIR..."
if ! touch "$WORKDIR/test_write" 2>/dev/null; then
    log "Cannot write to $WORKDIR. Attempting to fix permissions..."
    log_command "sudo chown $USER:$USER $WORKDIR"
    check_success $? "Fixing permissions for $WORKDIR"
    if ! touch "$WORKDIR/test_write" 2>/dev/null; then
        log "Still cannot write to $WORKDIR. Check permissions."
        exit 1
    fi
fi
rm -f "$WORKDIR/test_write"
log "Write permissions for $WORKDIR confirmed."

# Check if Minikube is running
log "Checking Minikube status..."
log_command "minikube status"
check_success $? "Checking Minikube status"

# Install make if not present
if ! command_exists make; then
    log "Installing make..."
    log_command "sudo apt update"
    check_success $? "apt update"
    log_command "sudo apt install -y make"
    check_success $? "Installing make"
else
    log "make is already installed."
fi

# Install git if not present
if ! command_exists git; then
    log "Installing git..."
    log_command "sudo apt update"
    check_success $? "apt update"
    log_command "sudo apt install -y git"
    check_success $? "Installing git"
else
    log "git is already installed."
fi

# Check if ingress addon is enabled
log "Checking Minikube ingress addon..."
INGRESS_STATUS=$(minikube addons list | grep ingress | awk '{print $2}')
if [ "$INGRESS_STATUS" != "enabled" ]; then
    log "Enabling Minikube ingress addon..."
    log_command "minikube addons enable ingress"
    check_success $? "Enabling ingress addon"
    log "Waiting for ingress controller to be ready..."
    for i in {1..60}; do
        if kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --no-headers 2>/dev/null | grep -q Running; then
            log "Ingress controller is ready."
            break
        fi
        log "Waiting for ingress controller..."
        sleep 5
    done
    if ! kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --no-headers 2>/dev/null | grep -q Running; then
        log "Ingress controller not ready after 5 minutes."
        exit 1
    fi
else
    log "Ingress addon is already enabled."
fi

# Create namespace if it doesn't exist
log "Creating namespace $NAMESPACE if it doesn't exist..."
log_command "kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -"
check_success $? "Creating namespace $NAMESPACE"

# Clone AWX operator repository
log "Cloning AWX operator repository..."
if [ ! -d "$WORKDIR/awx-operator" ]; then
    log_command "sudo git clone https://github.com/ansible/awx-operator.git $WORKDIR/awx-operator"
    check_success $? "Cloning AWX operator repository"
else
    log "awx-operator directory already exists, skipping clone."
fi

# Change to awx-operator directory
cd "$WORKDIR/awx-operator" || { log "Failed to change to awx-operator directory."; exit 1; }

# Checkout the latest AWX operator version
log "Checking out AWX operator version $AWX_OPERATOR_VERSION..."
log_command "git checkout tags/$AWX_OPERATOR_VERSION"
check_success $? "Checking out AWX operator version"

# Deploy AWX operator
log "Deploying AWX operator..."
log_command "make deploy"
check_success $? "Deploying AWX operator"

# Create AWX instance configuration
log "Creating AWX instance configuration..."
cat << EOF > awx-demo.yml
---
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-demo
  namespace: $NAMESPACE
spec:
  service_type: nodeport
EOF
log_command "cat awx-demo.yml"
check_success $? "Creating awx-demo.yml"

# Apply AWX instance configuration
log "Applying AWX instance configuration..."
log_command "kubectl apply -f awx-demo.yml -n $NAMESPACE"
check_success $? "Applying AWX instance configuration"

# Wait for AWX deployment to be ready
log "Waiting for AWX deployment to be ready..."
log_command "kubectl wait --for=condition=available --timeout=600s deployment/awx-demo -n $NAMESPACE"
check_success $? "Waiting for AWX deployment"

# Wait for AWX postgres pod to be ready
log "Waiting for AWX postgres pod to be ready..."
log_command "kubectl wait --for=condition=ready pod -l app=awx-postgres -n $NAMESPACE --timeout=600s"
check_success $? "Waiting for AWX postgres pod"

# Get AWX UI URL
log "Retrieving AWX UI URL..."
AWX_URL=$(minikube service -n $NAMESPACE awx-demo-service --url | head -n 1)
if [ -z "$AWX_URL" ]; then
    log "Failed to retrieve AWX UI URL."
    exit 1
fi
log "AWX UI URL: $AWX_URL"

# Get AWX admin password
log "Retrieving AWX admin password..."
AWX_PASSWORD=$(kubectl get secret awx-demo-admin-password -n $NAMESPACE -o jsonpath="{.data.password}" | base64 --decode)
if [ -z "$AWX_PASSWORD" ]; then
    log "Failed to retrieve AWX admin password."
    exit 1
fi
log "AWX admin username: admin"
log "AWX admin password: $AWX_PASSWORD"

# Verify installation
log "Verifying AWX installation..."
log_command "kubectl get pods -n $NAMESPACE"
check_success $? "Checking AWX pods"

# Completion message and summary
log "=== Script Completion Summary ==="
log "AWX Operator Version: $AWX_OPERATOR_VERSION"
log "AWX UI URL: $AWX_URL"
log "AWX Admin Username: admin"
log "AWX Admin Password: $AWX_PASSWORD"
log "Log file: $LOGFILE"
log "To access AWX, visit the AWX UI URL in your browser and log in with the admin credentials."
log "For issues, review $LOGFILE and AWX operator logs with 'kubectl logs -f deployments/awx-operator-controller-manager -c awx-manager -n $NAMESPACE'."