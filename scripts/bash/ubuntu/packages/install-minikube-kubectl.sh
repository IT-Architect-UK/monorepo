#!/bin/bash

# Script to install Minikube and kubectl on Ubuntu 24.04, deploying a single-node Kubernetes cluster
# Uses Docker as the container runtime (assumes Docker is pre-installed)
# Uses Minikube's default network setup
# Prepares environment for Portainer Agent (installed separately)
# Configures kubeconfig and systemd auto-start
# Preserves existing IPTABLES rules and adds necessary new rules
# Includes diagnostic tests for Kubernetes setup
# Uses variables for server names and IPs to enhance security

# Prompt for sudo password at the start
sudo -v

# Determine the original non-root user
if [ -n "$SUDO_USER" ] && id "$SUDO_USER" >/dev/null 2>&1; then
    ORIGINAL_USER="$SUDO_USER"
elif [ -n "$USER" ] && id "$USER" >/dev/null 2>&1; then
    ORIGINAL_USER="$USER"
else
    ORIGINAL_USER="$(whoami)"
fi
# Verify the user exists
if ! id "$ORIGINAL_USER" >/dev/null 2>&1; then
    echo "ERROR: Cannot determine valid non-root user"
    exit 1
fi
echo "Detected non-root user: $ORIGINAL_USER"

# Define variables
LOG_FILE="/var/log/minikube_install_$(date +%Y%m%d_%H%M%S).log"
DIAG_FILE="/tmp/minikube_diag_$(date +%Y%m%d_%H%M%S).txt"
MIN_MEMORY_MB=4096
MIN_CPUS=2
MIN_DISK_GB=20
TEMP_DIR="/tmp"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/minikube.service"
PORTAINER_K8S_NODEPORT=30778
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

# Run diagnostic test function
run_test() {
    local description="$1"
    local command="$2"
    local result="PASSED"
    local output
    echo "TEST: $description"
    log "Running test: $description"
    output=$($command 2>&1)
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
    sudo -u "$ORIGINAL_USER" bash -c "echo \"$description: $result\" >> $DIAG_FILE"
}

# Create log file with sudo
log "Creating log file at $LOG_FILE"
sudo touch "$LOG_FILE"
check_status "Creating log file"
sudo chown "$ORIGINAL_USER":"$ORIGINAL_USER" "$LOG_FILE"

# Create diagnostic file with sudo
log "Creating diagnostic file at $DIAG_FILE"
sudo touch "$DIAG_FILE"
check_status "Creating diagnostic file"
sudo chown "$ORIGINAL_USER":"$ORIGINAL_USER" "$DIAG_FILE"

# Detect server details
log "Detecting local server details"
if [ -z "$KUBE_SERVER_IP" ]; then
    log "ERROR: Could not determine server IP"
    exit 1
fi
log "Using $KUBE_SERVER for Kubernetes API"

# Check /etc/hosts
log "Checking /etc/hosts for $KUBE_SERVER"
if ! sudo grep -q "$KUBE_SERVER" /etc/hosts; then
    log "Adding $KUBE_SERVER to /etc/hosts"
    echo "$KUBE_SERVER_IP $KUBE_SERVER" | sudo tee -a /etc/hosts
    check_status "Updating /etc/hosts"
else
    log "$KUBE_SERVER already configured in /etc/hosts"
fi

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

# Clean up existing Minikube instance
log "Cleaning up existing Minikube instance"
sudo -u "$ORIGINAL_USER" minikube delete || true

# Start Minikube as the original user with default network
log "Starting Minikube with default network"
sudo -u "$ORIGINAL_USER" minikube start --driver=docker --apiserver-ips="$KUBE_SERVER_IP" --apiserver-port="$KUBERNETES_PORT" --memory="$MIN_MEMORY_MB" --cpus="$MIN_CPUS" --disk-size="${MIN_DISK_GB}g"
check_status "Starting Minikube"

# Capture Minikube IP
log "Capturing Minikube IP"
MINIKUBE_IP=$(sudo -u "$ORIGINAL_USER" minikube ip)
if [ -z "$MINIKUBE_IP" ]; then
    log "ERROR: Could not determine Minikube IP"
    exit 1
fi
log "Minikube IP: $MINIKUBE_IP"

# Configure kubeconfig as the original user
log "Configuring kubeconfig"
sudo -u "$ORIGINAL_USER" minikube update-context
sudo -u "$ORIGINAL_USER" kubectl config use-context minikube

# Verify API server connectivity
log "Verifying Kubernetes API server"
sudo -u "$ORIGINAL_USER" kubectl cluster-info
check_status "Verifying Kubernetes API server"

# Configure IPTables for Kubernetes API and Portainer Agent NodePort
log "Configuring IPTables rules"
sudo iptables -A INPUT -p tcp --dport "$PORTAINER_K8S_NODEPORT" -j ACCEPT
sudo iptables -A INPUT -p tcp --dport "$KUBERNETES_PORT" -j ACCEPT
# NAT rule for external access
sudo iptables -t nat -A PREROUTING -p tcp -d "$KUBE_SERVER_IP" --dport "$KUBERNETES_PORT" -j DNAT --to-destination "$MINIKUBE_IP:$KUBERNETES_PORT"
# NAT rule for local access (127.0.1.1)
sudo iptables -t nat -A PREROUTING -p tcp -d 127.0.1.1 --dport "$KUBERNETES_PORT" -j DNAT --to-destination "$MINIKUBE_IP:$KUBERNETES_PORT"
sudo iptables -t nat -A POSTROUTING -p tcp -d "$MINIKUBE_IP" --dport "$KUBERNETES_PORT" -j MASQUERADE
sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null
check_status "Configuring IPTables rules"

# Configure systemd service for Minikube
log "Configuring systemd service for Minikube"
if [ ! -f "$SYSTEMD_SERVICE_FILE" ]; then
    sudo bash -c "cat << EOF > $SYSTEMD_SERVICE_FILE
[Unit]
Description=Minikube Kubernetes Cluster
After=network.target docker.service
Requires=docker.service

[Service]
User=$ORIGINAL_USER
Group=docker
ExecStart=/usr/local/bin/minikube start --driver=docker --apiserver-ips=$KUBE_SERVER_IP --apiserver-port=$KUBERNETES_PORT --memory=$MIN_MEMORY_MB --cpus=$MIN_CPUS --disk-size=${MIN_DISK_GB}g
ExecStop=/usr/local/bin/minikube stop
Restart=on-failure
RestartSec=10
Environment=\"HOME=/home/$ORIGINAL_USER\"

[Install]
WantedBy=multi-user.target
EOF"
    sudo systemctl daemon-reload
    sudo systemctl enable minikube.service
    check_status "Configuring systemd service"
else
    log "Systemd service already configured"
fi

# Run diagnostic tests
log "Running diagnostic tests"
sudo -u "$ORIGINAL_USER" bash -c "echo '=============================================================' >> $DIAG_FILE"
sudo -u "$ORIGINAL_USER" bash -c "echo 'Diagnostic Test Results' >> $DIAG_FILE"
sudo -u "$ORIGINAL_USER" bash -c "echo '=============================================================' >> $DIAG_FILE"
run_test "Check Minikube status" "sudo -u \"$ORIGINAL_USER\" minikube status"
run_test "Check kubectl client version" "sudo -u \"$ORIGINAL_USER\" kubectl version --client"
run_test "Check Kubernetes nodes" "sudo -u \"$ORIGINAL_USER\" kubectl get nodes"
run_test "Check Kubernetes API connectivity (local)" "curl -k https://$MINIKUBE_IP:$KUBERNETES_PORT"
run_test "Check Kubernetes API connectivity (external)" "curl -k https://$KUBE_SERVER:$KUBERNETES_PORT"

# Display diagnostic summary
log "Displaying diagnostic summary"
echo "============================================================="
echo "Diagnostic Test Summary"
echo "============================================================="
sudo cat "$DIAG_FILE"
echo "============================================================="
sudo rm -f "$DIAG_FILE"

log "Minikube and kubectl installation completed successfully"