#!/bin/bash

# Script to install Ansible AWX on a Minikube Kubernetes cluster on Ubuntu 24.04
# Deploys the AWX Operator and an AWX instance, configures port forwarding, and verifies the setup
# Ensures Minikube and AWX restart after system reboot via systemd service
# Assumes Docker, Minikube, and kubectl are pre-installed and configured (e.g., via install-minikube-kubectl.sh)
# Uses Minikube's default network setup
# Preserves existing iptables rules
# Includes verbose logging and diagnostic tests

# Prerequisites:
# - Docker installed and running, with the user in the docker group
# - Minikube installed and a cluster running with sufficient resources (4 CPUs, 8 GB RAM, 20 GB disk)
# - kubectl installed and configured to interact with the Minikube cluster
# - Ubuntu 24.04 as the operating system
# - Internet access to download AWX Operator manifests and container images
# - Non-root user with sudo privileges

# Prompt for sudo password at the start
sudo -v

# Determine the original non-root user
if [ -n "$SUDO_USER" ] && id "$SUDO_USER" >/dev/null 2>&1; then
    ORIGINAL_USER="$SUDO_USER"
else
    ORIGINAL_USER="$(id -un)"
fi
# Verify the user exists
if ! id "$ORIGINAL_USER" >/dev/null 2>&1; then
    echo "ERROR: Cannot determine valid non-root user"
    exit 1
fi
echo "Detected non-root user: $ORIGINAL_USER"

# Define variables
LOG_FILE="/var/log/awx_install_$(date +%Y%m%d_%H%M%S).log"
DIAG_FILE="/tmp/awx_diag_$(date +%Y%m%d_%H%M%S).txt"
TEMP_DIR="/tmp"
AWX_NAMESPACE="awx"
KUBERNETES_PORT=8443
KUBECONFIG="/home/$ORIGINAL_USER/.kube/config"
KUBE_SERVER="$(hostname -f)"
KUBE_SERVER_IP="$(ip -4 addr show | grep inet | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n 1)"
export LOG_FILE
export KUBECONFIG

# Log function
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | sudo tee -a "$LOG_FILE"
}

# Check status function
check_status() {
    if [ $? -ne 0 ]; then
        log "ERROR: $1 failed"
        exit 1
    fi
}

# Run diagnostic test function with explicit command logging
run_test() {
    local description="$1"
    local command="$2"
    local result="PASSED"
    local output
    echo "TEST: $description"
    echo "Executing command: $command"
    log "Running test: $description"
    log "Executing command: $command"
    output=$(eval "$command" 2>&1)
    if [ $? -ne 0 ]; then
        result="FAILED"
        echo "Result: FAILED"
        echo "Error: $output"
        log "$description: FAILED"
        log "Error: $output"
    else
        echo "Result: PASSED"
        log "$description: PASSED"
        log "Output: $output"
    fi
    echo "----------------------------------------"
    echo "$description: $result" >> "$DIAG_FILE"
}

# Create log file with sudo
log "Creating log file at $LOG_FILE"
sudo touch "$LOG_FILE"
check_status "Creating log file"
sudo chown "$ORIGINAL_USER":"$ORIGINAL_USER" "$LOG_FILE"

# Create diagnostic file
log "Creating diagnostic file at $DIAG_FILE"
touch "$DIAG_FILE"
check_status "Creating diagnostic file"
chmod 644 "$DIAG_FILE"

# Validate prerequisites
log "Validating prerequisites"

# Check Docker
log "Checking Docker installation and access"
if ! command -v docker >/dev/null 2>&1; then
    log "ERROR: Docker is not installed"
    exit 1
fi
sudo -H -u "$ORIGINAL_USER" bash -c "docker ps >/dev/null 2>&1"
check_status "Docker access verification"

# Check Minikube
log "Checking Minikube installation"
if ! command -v minikube >/dev/null 2>&1; then
    log "ERROR: Minikube is not installed"
    exit 1
fi
sudo -H -u "$ORIGINAL_USER" bash -c "minikube status >/dev/null 2>&1"
check_status "Minikube status verification"

# Get Minikube IP
log "Retrieving Minikube IP"
MINIKUBE_IP=$(sudo -H -u "$ORIGINAL_USER" bash -c "minikube ip")
if [ -z "$MINIKUBE_IP" ]; then
    log "ERROR: Could not retrieve Minikube IP. Ensure Minikube is running."
    exit 1
fi
log "Minikube IP: $MINIKUBE_IP"

# Check kubectl
log "Checking kubectl installation"
if ! command -v kubectl >/dev/null 2>&1; then
    log "ERROR: kubectl is not installed"
    exit 1
fi
sudo -H -u "$ORIGINAL_USER" bash -c "kubectl cluster-info >/dev/null 2>&1"
check_status "kubectl cluster access verification"

# Detect server details
log "Detecting local server details"
if [ -z "$KUBE_SERVER_IP" ]; then
    log "ERROR: Could not determine server IP"
    exit 1
fi
log "Using $KUBE_SERVER for Kubernetes API"

# Get latest AWX Operator release tag
log "Fetching latest AWX Operator release tag"
RELEASE_TAG=$(curl -s https://api.github.com/repos/ansible/awx-operator/releases/latest | grep tag_name | cut -d '"' -f 4)
if [ -z "$RELEASE_TAG" ]; then
    log "ERROR: Could not fetch AWX Operator release tag"
    exit 1
fi
log "Latest AWX Operator release tag: $RELEASE_TAG"

# Create AWX namespace
log "Creating AWX namespace"
sudo -H -u "$ORIGINAL_USER" bash -c "kubectl create namespace $AWX_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -"
check_status "Creating AWX namespace"

# Deploy AWX Operator
log "Deploying AWX Operator version $RELEASE_TAG"
sudo -H -u "$ORIGINAL_USER" bash -c "kubectl apply -f https://raw.githubusercontent.com/ansible/awx-operator/refs/tags/$RELEASE_TAG/deploy/awx-operator.yaml -n $AWX_NAMESPACE"
check_status "Deploying AWX Operator"

# Wait for AWX Operator to be ready
log "Waiting for AWX Operator to be ready"
sudo -H -u "$ORIGINAL_USER" bash -c "kubectl wait --for=condition=available --timeout=300s deployment/awx-operator-controller-manager -n $AWX_NAMESPACE"
check_status "Waiting for AWX Operator"

# Create AWX instance manifest
log "Creating AWX instance manifest"
sudo -H -u "$ORIGINAL_USER" bash -c "cat << EOF > $TEMP_DIR/awx-demo.yml
apiVersion: awx.ansible.com/v1beta1
kind: AWX
metadata:
  name: awx-demo
  namespace: $AWX_NAMESPACE
spec:
  service_type: nodeport
EOF"
check_status "Creating AWX instance manifest"

# Deploy AWX instance
log "Deploying AWX instance"
sudo -H -u "$ORIGINAL_USER" bash -c "kubectl apply -f $TEMP_DIR/awx-demo.yml -n $AWX_NAMESPACE"
check_status "Deploying AWX instance"

# Wait for AWX instance to be ready
log "Waiting for AWX instance to be ready"
sudo -H -u "$ORIGINAL_USER" bash -c "kubectl wait --for=condition=available --timeout=600s deployment/awx-demo -n $AWX_NAMESPACE"
check_status "Waiting for AWX instance"

# Get NodePort for AWX service
log "Retrieving AWX service NodePort"
NODE_PORT=$(sudo -H -u "$ORIGINAL_USER" bash -c "kubectl get svc awx-demo-service -n $AWX_NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}'")
if [ -z "$NODE_PORT" ]; then
    log "ERROR: Could not retrieve AWX service NodePort"
    exit 1
fi
log "AWX service NodePort: $NODE_PORT"

# Get AWX admin password
log "Retrieving AWX admin password"
ADMIN_PASSWORD=$(sudo -H -u "$ORIGINAL_USER" bash -c "kubectl get secret awx-demo-admin-password -n $AWX_NAMESPACE -o jsonpath='{.data.password}' | base64 --decode")
if [ -z "$ADMIN_PASSWORD" ]; then
    log "ERROR: Could not retrieve AWX admin password"
    exit 1
fi
log "AWX admin password retrieved successfully"

# Create systemd service for Minikube and AWX auto-restart
log "Creating systemd service for Minikube and AWX auto-restart"
cat << EOF | sudo tee /etc/systemd/system/minikube-awx.service
[Unit]
Description=Minikube and AWX Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/bin/bash -c 'minikube start --driver=docker --cpus=8 --memory=16384 && kubectl create namespace $AWX_NAMESPACE --dry-run=client -o yaml | kubectl apply -f - && kubectl apply -f https://raw.githubusercontent.com/ansible/awx-operator/refs/tags/$RELEASE_TAG/deploy/awx-operator.yaml -n $AWX_NAMESPACE && kubectl wait --for=condition=available --timeout=300s deployment/awx-operator-controller-manager -n $AWX_NAMESPACE && kubectl apply -f $TEMP_DIR/awx-demo.yml -n $AWX_NAMESPACE && kubectl wait --for=condition=available --timeout=600s deployment/awx-demo -n $AWX_NAMESPACE && POD_NAME=\$(kubectl get pod -n $AWX_NAMESPACE -l k8s-app=kubernetes-dashboard -o jsonpath='{.items[0].metadata.name}') && kubectl port-forward --address 0.0.0.0 pods/\$POD_NAME 8001:9090 -n $AWX_NAMESPACE'
ExecStop=/bin/bash -c 'minikube stop'
Restart=always
RestartSec=10
User=$ORIGINAL_USER

[Install]
WantedBy=multi-user.target
EOF
check_status "Creating systemd service file"

# Enable and start the service
log "Enabling and starting minikube-awx service"
log_command "sudo systemctl enable minikube-awx.service"
check_status "Enabling minikube-awx service"
log_command "sudo systemctl start minikube-awx.service"
check_status "Starting minikube-awx service"

# Display AWX access details
echo "AWX Installation Complete!"
echo "Access the AWX web interface at: http://$MINIKUBE_IP:$NODE_PORT"
echo "Username: admin"
echo "Password: $ADMIN_PASSWORD"
log "AWX access details: http://$MINIKUBE_IP:$NODE_PORT, Username: admin, Password: [redacted]"

# Run diagnostic tests
log "Running diagnostic tests"
echo "=============================================================" >> "$DIAG_FILE"
echo "Diagnostic Test Results" >> "$DIAG_FILE"
echo "=============================================================" >> "$DIAG_FILE"
run_test "Check AWX Operator pods" "kubectl get pods -n $AWX_NAMESPACE -l 'app.kubernetes.io/managed-by=awx-operator'"
run_test "Check AWX service" "kubectl get svc awx-demo-service -n $AWX_NAMESPACE"
run_test "Check AWX web interface" "curl -k -s -o /dev/null -w '%{http_code}' http://$MINIKUBE_IP:$NODE_PORT"

# Display diagnostic summary
log "Displaying diagnostic summary"
echo "============================================================="
echo "Diagnostic Test Summary"
echo "============================================================="
cat "$DIAG_FILE"
echo "============================================================="
rm -f "$DIAG_FILE"

log "AWX installation completed successfully"