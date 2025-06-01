#!/bin/bash

# === Minikube Installation Script ===
# Purpose: Installs Minikube, kubectl, enables the Minikube dashboard, and sets up auto-restart after reboot.
# Target System: Ubuntu 24.04 (clean install)
# Resources Allocated: 8 CPUs, 16GB RAM for Minikube
# Requirements: Sudo privileges, Internet access, Minimum 32GB RAM and 16 vCPUs
# Logs: Actions logged to /logs/install_minikube_<timestamp>.log
# Note: Uses Docker as the Minikube driver.

# Define variables
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOGFILE="/logs/install_minikube_${TIMESTAMP}.log"
MINIKUBE_CPUS=8
MINIKUBE_MEMORY=16384
LOCAL_PORT=8001
CONTAINER_PORT=8443
KUBECONFIG_PATH="/home/$USER/.kube/config"

# Create /logs directory
sudo mkdir -p /logs

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
check_success $? "Obtaining sudo privileges"

# Check write permissions for /tmp
log "Checking write permissions for /tmp..."
touch /tmp/test_write 2>/dev/null
check_success $? "Write permissions for /tmp"
rm -f /tmp/test_write

# Install Docker if not present
if ! command_exists docker; then
    log "Installing Docker..."
    log_command "sudo apt update"
    check_success $? "apt update"
    log_command "sudo apt install -y apt-transport-https ca-certificates curl software-properties-common"
    check_success $? "Installing dependencies"
    log_command "sudo install -m 0755 -d /etc/apt/keyrings"
    check_success $? "Creating keyrings directory"
    log_command "sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc"
    check_success $? "Downloading Docker GPG key"
    log_command "sudo chmod a+r /etc/apt/keyrings/docker.asc"
    check_success $? "Setting permissions for Docker GPG key"
    log_command "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null"
    check_success $? "Adding Docker repository"
    log_command "sudo apt update"
    check_success $? "apt update after adding Docker repository"
    log_command "sudo apt install -y docker-ce docker-ce-cli containerd.io"
    check_success $? "Installing Docker"
    log_command "docker --version"
    check_success $? "Checking Docker version"
else
    log "Docker is already installed."
fi

# Verify docker group and add user
getent group docker > /dev/null
check_success $? "Verifying docker group exists"
if ! groups | grep -q docker; then
    log "Adding user to docker group..."
    sudo usermod -aG docker "$USER"
    check_success $? "Adding user to docker group"
    log "Please log out and log back in for group changes to take effect, then run this script again."
    exit 0
fi

# Install kubectl if not present
if ! command_exists kubectl; then
    log "Installing kubectl..."
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    log_command "curl -L \"https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl\" -o /tmp/kubectl"
    check_success $? "Downloading kubectl"
    log_command "chmod +x /tmp/kubectl"
    check_success $? "Making kubectl executable"
    log_command "sudo mv /tmp/kubectl /usr/local/bin/"
    check_success $? "Moving kubectl to /usr/local/bin"
    log_command "kubectl version --client"
    check_success $? "Checking kubectl version"
else
    log "kubectl is already installed."
fi

# Install minikube if not present
if ! command_exists minikube; then
    log "Installing minikube..."
    log_command "curl -L https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 -o /tmp/minikube"
    check_success $? "Downloading minikube"
    log_command "chmod +x /tmp/minikube"
    check_success $? "Making minikube executable"
    log_command "sudo mv /tmp/minikube /usr/local/bin/"
    check_success $? "Moving minikube to /usr/local/bin"
    log_command "minikube version"
    check_success $? "Checking minikube version"
else
    log "minikube is already installed."
fi

# Check available resources
log "Checking available resources..."
AVAILABLE_CPUS=$(nproc)
AVAILABLE_MEM=$(free -m | awk '/^Mem:/{print $2}')
log "Available CPUs: $AVAILABLE_CPUS"
log "Available memory: $AVAILABLE_MEM MB"
[ "$AVAILABLE_CPUS" -lt "$MINIKUBE_CPUS" ] && log "Warning: Available CPUs less than $MINIKUBE_CPUS."
[ "$AVAILABLE_MEM" -lt "$MINIKUBE_MEMORY" ] && log "Warning: Available memory less than $MINIKUBE_MEMORY MB."

# Start Minikube
log "Starting Minikube..."
log_command "minikube start --driver=docker --cpus=$MINIKUBE_CPUS --memory=$MINIKUBE_MEMORY"
check_success $? "Starting Minikube"
log_command "minikube update-context"
check_success $? "Updating Minikube kubeconfig context"

# Enable Minikube dashboard
log "Enabling Minikube dashboard..."
log_command "minikube addons enable dashboard"
check_success $? "Enabling Minikube dashboard"

# Enable metrics-server addon
log "Enabling metrics-server addon..."
log_command "minikube addons enable metrics-server"
check_success $? "Enabling metrics-server addon"

# Fix RBAC issues
log "Applying RBAC rolebindings..."
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: kube-system
  name: node-role
rules:
- apiGroups: [""]
  resources: ["pods", "configmaps"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["storage.k8s.io"]
  resources: ["csidrivers", "csinodes", "storageclasses"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: kube-system
  name: node-binding
subjects:
- kind: User
  name: system:node:minikube
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: node-role
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: kube-system
  name: extension-apiserver-authentication-reader-binding
subjects:
- kind: User
  name: system:kube-scheduler
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: extension-apiserver-authentication-reader
  apiGroup: rbac.authorization.k8s.io
EOF
check_success $? "Applying RBAC rolebindings"

# Verify dashboard service
log "Verifying dashboard service..."
log_command "kubectl get svc -n kubernetes-dashboard -l k8s-app=kubernetes-dashboard"
check_success $? "Verifying dashboard service"

# Wait for dashboard pod
log "Waiting for dashboard pod..."
for i in {1..60}; do
    POD_NAME=$(kubectl get pod -n kubernetes-dashboard -l k8s-app=kubernetes-dashboard -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    [ -n "$POD_NAME" ] && break
    log "No dashboard pod found yet. Waiting..."
    sleep 5
done
[ -z "$POD_NAME" ] && { log "No dashboard pod found after 5 minutes."; exit 1; }
log "Dashboard pod found: $POD_NAME"

# Wait for dashboard pod to be ready
log "Waiting for dashboard pod to be ready..."
for i in {1..3}; do
    log_command "kubectl wait --for=condition=ready pod/$POD_NAME -n kubernetes-dashboard --timeout=300s"
    [ $? -eq 0 ] && break
    log "Dashboard pod not ready. Retrying ($i/3)..."
    sleep 10
done
check_success $? "Waiting for dashboard pod"

# Start port-forward with retry
log "Starting port-forward for dashboard LAN access on port $LOCAL_PORT..."
for i in {1..3}; do
    pkill -f "kubectl port-forward" 2>/dev/null
    log_command "kubectl port-forward --address 0.0.0.0 pods/$POD_NAME $LOCAL_PORT:$CONTAINER_PORT -n kubernetes-dashboard > /tmp/port-forward.log 2>&1 &"
    sleep 10
    pgrep -f "kubectl port-forward" > /dev/null && ss -tuln | grep -q ":$LOCAL_PORT" && break
    log "Port-forward attempt $i failed. Retrying..."
    sleep 5
done
pgrep -f "kubectl port-forward" > /dev/null
check_success $? "Starting port-forward process"

# Test dashboard access
log "Testing dashboard access locally..."
sleep 10
curl --max-time 30 -s "http://127.0.0.1:$LOCAL_PORT" | grep -q "Kubernetes Dashboard"
if [ $? -eq 0 ]; then
    log "Accessing dashboard locally succeeded."
    SERVER_IP=$(hostname -I | awk '{print $1}')
    DASHBOARD_URL="http://$SERVER_IP:$LOCAL_PORT"
    log "Dashboard accessible at: $DASHBOARD_URL"
else
    log "Warning: Dashboard access test failed. Check /tmp/port-forward.log for details."
fi

# Create systemd service
log "Creating systemd service for Minikube and dashboard auto-restart..."
cat << EOF | sudo tee /etc/systemd/system/minikube.service
[Unit]
Description=Minikube and Kubernetes Dashboard Service
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
Environment="KUBECONFIG=$KUBECONFIG_PATH"
ExecStart=/bin/bash -c 'minikube start --driver=docker --cpus=$MINIKUBE_CPUS --memory=$MINIKUBE_MEMORY && minikube update-context && minikube addons enable dashboard && minikube addons enable metrics-server && sleep 10 && POD_NAME=\$(kubectl get pod -n kubernetes-dashboard -l k8s-app=kubernetes-dashboard -o jsonpath='{.items[0].metadata.name}') && kubectl port-forward --address 0.0.0.0 pods/\$POD_NAME $LOCAL_PORT:$CONTAINER_PORT -n kubernetes-dashboard'
ExecStop=/bin/bash -c 'minikube stop'
Restart=always
RestartSec=10
User=$USER

[Install]
WantedBy=multi-user.target
EOF
check_success $? "Creating systemd service file"

# Enable and start the service
log "Enabling and starting minikube service..."
log_command "sudo systemctl daemon-reload"
check_success $? "Reloading systemd daemon"
log_command "sudo systemctl enable minikube.service"
check_success $? "Enabling minikube service"
log_command "sudo systemctl start minikube.service"
check_success $? "Starting minikube service"

# Verify installation
log "Verifying installation..."
log_command "minikube status"
check_success $? "Checking Minikube status"
log_command "kubectl cluster-info"
check_success $? "Checking cluster info"

# Completion message
log "=== Script Completion Summary ==="
log "Minikube Status: $(minikube status | grep -E 'host|kubelet|apiserver' || echo 'Status unavailable')"
log "kubectl Version: $(kubectl version --client --output=yaml | grep gitVersion || echo 'Version unavailable')"
log "Kubernetes Dashboard: Accessible at $DASHBOARD_URL (if test succeeded)"
log "Remote Management: Copy ~/.kube/config to your local machine, set KUBECONFIG=~/.kube/config, and use 'kubectl' commands."
log "Log file: $LOGFILE"
log "To stop dashboard access manually, run: pkill -f 'kubectl port-forward'"
log "To manage the service, use: systemctl {start|stop|restart|status} minikube.service"