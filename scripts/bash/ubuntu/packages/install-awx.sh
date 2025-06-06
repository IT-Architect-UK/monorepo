#!/bin/bash

# === AWX Installation Script ===
# Purpose: Installs AWX on a Minikube cluster using the AWX Operator.
# Target System: Ubuntu 24.04 with Minikube (Docker driver)
# Resources Allocated: Ensures Minikube has 8 CPUs, 16GB RAM
# Requirements:
#   - Sudo privileges
#   - Internet access
#   - Minikube running with kubectl configured
#   - Git installed
#   - Curl installed for AWX availability check
# Logs: All actions and statuses will be logged to /logs/install_awx_<timestamp>.log for troubleshooting.
# Note: This script ensures Minikube resource allocation and debug logging for AWX pod issues.
# ==============================

# Define variables
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOGFILE="/logs/install_awx_${TIMESTAMP}.log"
NAMESPACE="ansible-awx"
OPERATOR_NAMESPACE="awx"
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

# Ensure Minikube resource allocation
log "Ensuring Minikube resource allocation (8 CPUs, 16GB memory)..."
log_command "minikube config set cpus 8"
check_success $? "Setting Minikube CPUs"
log_command "minikube config set memory 16384"
check_success $? "Setting Minikube memory"
log_command "minikube stop"
check_success $? "Stopping Minikube"
log_command "minikube start"
check_success $? "Starting Minikube"

# Verify Minikube resources
log "Verifying Minikube resource allocation..."
log_command "minikube config get cpus"
check_success $? "Checking Minikube CPUs"
log_command "minikube config get memory"
check_success $? "Checking Minikube memory"
log_command "minikube ssh -- docker info --format '{{.NCPU}} {{.MemTotal}}'"
check_success $? "Checking Minikube VM resources"

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

# Install curl if not present
if ! command_exists curl; then
    log "Installing curl..."
    log_command "sudo apt update"
    check_success $? "apt update"
    log_command "sudo apt install -y curl"
    check_success $? "Installing curl"
else
    log "curl is already installed."
fi

# Check if ingress addon is enabled
log "Checking Minikube ingress addon..."
INGRESS_STATUS=$(minikube addons list | grep ingress | awk '{print $2}')
if [ "$INGRESS_STATUS" != "enabled" ]; then
    log "Enabling Minikube ingress addon..."
    log_command "minikube addons enable ingress"
    check_success $? "Enabling ingress addon"
fi

# Ensure ingress-nginx-admission secret exists
log "Checking for ingress-nginx-admission secret..."
if ! kubectl get secret ingress-nginx-admission -n ingress-nginx --no-headers 2>/dev/null | grep -q ingress-nginx-admission; then
    log "ingress-nginx-admission secret not found. Recreating..."
    log_command "kubectl delete -n ingress-nginx secret ingress-nginx-admission --ignore-not-found"
    log_command "minikube addons disable ingress && minikube addons enable ingress"
    check_success $? "Recreating ingress-nginx-admission secret"
fi
log "Waiting for ingress controller to be ready..."
for i in {1..120}; do
    if kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --no-headers 2>/dev/null | grep -q Running; then
        log "Ingress controller is ready."
        break
    fi
    log "Waiting for ingress controller..."
    sleep 5
done
if ! kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --no-headers 2>/dev/null | grep -q Running; then
    log "Ingress controller not ready after 10 minutes."
    exit 1
fi

# Create namespaces if they don't exist
log "Creating namespace $NAMESPACE if it doesn't exist..."
log_command "kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -"
check_success $? "Creating namespace $NAMESPACE"

log "Creating namespace $OPERATOR_NAMESPACE if it doesn't exist..."
log_command "kubectl create namespace $OPERATOR_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -"
check_success $? "Creating namespace $OPERATOR_NAMESPACE"

# Create dummy redhat-operators-pull-secret in both namespaces
log "Creating dummy redhat-operators-pull-secret in namespace $OPERATOR_NAMESPACE..."
log_command "kubectl -n $OPERATOR_NAMESPACE create secret docker-registry redhat-operators-pull-secret --docker-server=dummy.example.com --docker-username=dummy --docker-password=dummy"
check_success $? "Creating dummy redhat-operators-pull-secret in $OPERATOR_NAMESPACE"

log "Creating dummy redhat-operators-pull-secret in namespace $NAMESPACE..."
log_command "kubectl -n $NAMESPACE create secret docker-registry redhat-operators-pull-secret --docker-server=dummy.example.com --docker-username=dummy --docker-password=dummy"
check_success $? "Creating dummy redhat-operators-pull-secret in $NAMESPACE"

# Verify secrets exist
log "Verifying redhat-operators-pull-secret in $OPERATOR_NAMESPACE..."
if ! kubectl get secret redhat-operators-pull-secret -n $OPERATOR_NAMESPACE --no-headers 2>/dev/null | grep -q redhat-operators-pull-secret; then
    log "redhat-operators-pull-secret not found in $OPERATOR_NAMESPACE."
    exit 1
fi
log "redhat-operators-pull-secret verified in $OPERATOR_NAMESPACE."

log "Verifying redhat-operators-pull-secret in $NAMESPACE..."
if ! kubectl get secret redhat-operators-pull-secret -n $NAMESPACE --no-headers 2>/dev/null | grep -q redhat-operators-pull-secret; then
    log "redhat-operators-pull-secret not found in $NAMESPACE."
    exit 1
fi
log "redhat-operators-pull-secret verified in $NAMESPACE."

# Clone AWX operator repository
log "Cloning AWX operator repository..."
if [ ! -d "$WORKDIR/awx-operator" ]; then
    log_command "sudo git clone https://github.com/ansible/awx-operator.git $WORKDIR/awx-operator"
    check_success $? "Cloning AWX operator repository"
    log "Fixing ownership of awx-operator directory..."
    log_command "sudo chown -R $USER:$USER $WORKDIR/awx-operator"
    check_success $? "Fixing ownership of awx-operator directory"
else
    log "awx-operator directory already exists, skipping clone."
fi

# Add awx-operator directory to Git safe directories
log "Adding $WORKDIR/awx-operator to Git safe directories..."
log_command "git config --global --add safe.directory $WORKDIR/awx-operator"
check_success $? "Adding awx-operator to Git safe directories"

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

# Check for image pull secret issues
log "Checking for AWX Operator pod events..."
log_command "kubectl get events -n $OPERATOR_NAMESPACE --field-selector involvedObject.kind=Pod"
if kubectl get events -n $OPERATOR_NAMESPACE 2>/dev/null | grep -q "FailedToRetrieveImagePullSecret"; then
    log "Warning: Image pull secret issue detected. AWX Operator may have issues pulling images."
fi

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

# Check AWX operator logs for errors
log "Checking AWX operator logs for errors..."
log_command "kubectl logs -n $OPERATOR_NAMESPACE -l app.kubernetes.io/name=awx-operator --tail=100"
check_success $? "Checking AWX operator logs"

# Check AWX custom resource status
log "Checking AWX custom resource status..."
log_command "kubectl describe awx awx-demo -n $NAMESPACE"
check_success $? "Checking AWX custom resource status"

# Wait for AWX custom resource to be created
log "Waiting for AWX custom resource to be created..."
for i in {1..60}; do
    if kubectl get awx awx-demo -n $NAMESPACE --no-headers 2>/dev/null | grep -q awx-demo; then
        log "AWX custom resource created."
        break
    fi
    log "Waiting for AWX custom resource..."
    sleep 5
done
if ! kubectl get awx awx-demo -n $NAMESPACE --no-headers 2>/dev/null | grep -q awx-demo; then
    log "AWX custom resource not found after 5 minutes."
    exit 1
fi

# Wait for AWX pods to be created (extended to 20 minutes)
log "Waiting for AWX pods to be created..."
for i in {1..240}; do
    if kubectl get pods -n $NAMESPACE -l app.kubernetes.io/part-of=awx --no-headers 2>/dev/null | grep -q .; then
        log "AWX pods found."
        break
    fi
    log "Waiting for AWX pods..."
    sleep 5
done
if ! kubectl get pods -n $NAMESPACE -l app.kubernetes.io/part-of=awx --no-headers 2>/dev/null | grep -q .; then
    log "No AWX pods found after 20 minutes."
    exit 1
fi

# Check for pod creation errors
log "Checking for AWX pod creation errors..."
log_command "kubectl get pods -n $NAMESPACE -l app.kubernetes.io/part-of=awx --no-headers"
log_command "kubectl describe pods -n $NAMESPACE -l app.kubernetes.io/part-of=awx"
check_success $? "Checking AWX pod creation"

# Wait for AWX pods to be ready
log "Waiting for AWX pods to be ready..."
log_command "kubectl wait --for=condition=ready pod -l app.kubernetes.io/part-of=awx -n $NAMESPACE --timeout=600s"
check_success $? "Waiting for AWX pods"

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

# Poll AWX to verify availability
log "Polling AWX to verify availability..."
for i in {1..120}; do
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$AWX_URL" --max-time 5)
    if [ "$HTTP_STATUS" -eq 200 ] || [ "$HTTP_STATUS" -eq 302 ]; then
        log "AWX is available (HTTP status: $HTTP_STATUS)."
        echo "AWX installation complete!"
        echo "Access AWX at: $AWX_URL"
        echo "Username: admin"
        echo "Password: $AWX_PASSWORD"
        break
    fi
    log "AWX not yet available (HTTP status: $HTTP_STATUS). Retrying in 5 seconds..."
    sleep 5
done
if [ "$HTTP_STATUS" != 200 ] && [ "$HTTP_STATUS" != 302 ]; then
    log "AWX not available after 10 minutes."
    exit 1
fi

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
log "For issues, review $LOGFILE and AWX operator logs with 'kubectl logs -f deployments/awx-operator-controller-manager -c awx-manager -n $OPERATOR_NAMESPACE'."