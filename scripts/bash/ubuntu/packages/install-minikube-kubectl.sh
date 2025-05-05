#!/bin/bash

# Script to install Minikube and kubectl on Ubuntu 24.04, deploying a single-node Kubernetes cluster
# Uses Docker as the container runtime (assumes Docker is pre-installed)
# Configures Docker and Minikube to use a user-specified network (default 172.18.0.0/16)
# Deploys Portainer agent for remote management
# Configures kubeconfig and systemd auto-start
# Preserves existing IPTABLES rules and adds only necessary new rules
# Includes diagnostic tests at the end for verification

# Exit on any error
set -e

# Define variables
LOG_FILE="/var/log/minikube_install_$(date +%Y%m%d_%H%M%S).log"
MIN_MEMORY_MB=4096
MIN_CPUS=2
MIN_DISK_GB=20
DOCKER_NETWORK="${DOCKER_NETWORK:-172.18.0.0/16}"
NON_ROOT_USER="$USER"
TEMP_DIR="/tmp"
SYSTEMD_SERVICE_FILE="/etc/systemd/system/minikube.service"
PORTAINER_AGENT_YAML="portainer-agent-k8s-nodeport.yaml"
PORTAINER_AGENT_URL="https://downloads.portainer.io/ce2-19/portainer-agent-k8s-nodeport.yaml"
PORTAINER_NODEPORT=30778
KUBERNETES_PORT=8443
export LOG_FILE

# Log function
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | sudo tee -a "$LOG_FILE" > /dev/null
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message"
}
export -f log

# Check status function
check_status() {
    if [ $? -ne 0 ]; then
        log "ERROR: $1 failed"
        exit 1
    fi
}

# Run test function for diagnostics
run_test() {
    local description="$1"
    local command="$2"
    log "Running test: $description"
    output=$($command 2>&1)
    if [ $? -eq 0 ]; then
        log "$description: PASSED"
        log "Output: $output"
    else
        log "$description: FAILED"
        log "Error: $output"
    fi
}

# Validate Docker network
validate_docker_network() {
    local network="$1"
    if ! echo "$network" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'; then
        log "ERROR: Invalid DOCKER_NETWORK format: $network"
        exit 1
    fi
    DOCKER_BIP=$(echo "$network" | awk -F'/' '{split($1,a,"."); print a[1]"."a[2]"."a[3]".1/"$2}')
    log "Calculated bridge IP: $DOCKER_BIP"
}

# Create log file
log "Creating log file at $LOG_FILE"
sudo mkdir -p "$(dirname "$LOG_FILE")"
sudo touch "$LOG_FILE"
sudo chmod 664 "$LOG_FILE"
sudo chown "$NON_ROOT_USER":"$NON_ROOT_USER" "$LOG_FILE"
check_status "Creating log file"

# Detect server details
log "Detecting local server details"
SERVER_IP=$(ip -4 addr show | grep inet | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
SERVER_FQDN=$(hostname -f)
KUBE_SERVER="${SERVER_FQDN:-$SERVER_IP}"
log "Using $KUBE_SERVER for Kubernetes API"

# Modify /etc/hosts if necessary
log "Checking /etc/hosts for $KUBE_SERVER"
if ! grep -q "$SERVER_IP $KUBE_SERVER" /etc/hosts; then
    log "Modifying /etc/hosts to prioritize $SERVER_IP for $KUBE_SERVER"
    sudo sed -i "/$KUBE_SERVER/d" /etc/hosts
    sudo sed -i "1i $SERVER_IP $KUBE_SERVER" /etc/hosts
    check_status "Modifying /etc/hosts"
else
    log "$KUBE_SERVER already configured in /etc/hosts"
fi

# Check sudo privileges
log "Checking sudo privileges"
sudo -n true 2>/dev/null || { log "ERROR: No sudo privileges"; exit 1; }

# Check and handle Docker group membership
log "Checking Docker group membership"
if ! groups | grep -q docker; then
    log "Adding user $NON_ROOT_USER to docker group"
    sudo usermod -aG docker "$NON_ROOT_USER"
    check_status "Adding user to docker group"
    log "WARNING: You have been added to the docker group. Please log out and back in, then re-run this script."
    log "Alternatively, run: sg docker -c './$0'"
    exit 1
fi

# Verify Docker access
log "Verifying Docker access"
if ! docker info &> /dev/null; then
    log "ERROR: User $NON_ROOT_USER cannot access Docker daemon. Ensure you are in the docker group and have logged out/in."
    exit 1
fi

# Configure Docker network
validate_docker_network "$DOCKER_NETWORK"
log "Configuring Docker network to $DOCKER_NETWORK"
if ! grep -q "\"bip\": \"$DOCKER_BIP\"" /etc/docker/daemon.json 2>/dev/null; then
    sudo mkdir -p /etc/docker
    echo "{\"bip\": \"$DOCKER_BIP\", \"fixed-cidr\": \"$DOCKER_NETWORK\", \"exec-opts\": [\"native.cgroupdriver=systemd\"]}" | sudo tee /etc/docker/daemon.json > /dev/null
    sudo systemctl restart docker
    check_status "Configuring Docker network"
else
    log "Docker network already configured for $DOCKER_NETWORK"
fi

# Remove conflicting Docker networks
log "Removing conflicting Docker networks"
for net in $(docker network ls --filter "driver=bridge" -q); do
    subnet=$(docker network inspect --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' "$net")
    if [ "$subnet" = "$DOCKER_NETWORK" ]; then
        log "Removing conflicting network: $net"
        docker network rm "$net" 2>/dev/null || true
    fi
done

# Backup current IPTABLES rules
IPTABLES_BACKUP="/tmp/iptables_backup_$(date +%Y%m%d_%H%M%S).rules"
log "Backing up current IPTABLES rules to $IPTABLES_BACKUP"
sudo iptables-save > "$IPTABLES_BACKUP"
check_status "Backing up IPTABLES rules"

# Add required rules if they don’t exist
log "Adding required IPTABLES rules if necessary"

# Rule for Kubernetes API port (8443)
if ! sudo iptables -C INPUT -p tcp --dport 8443 -j ACCEPT 2>/dev/null; then
    log "Adding rule for Kubernetes API port 8443"
    sudo iptables -A INPUT -p tcp --dport 8443 -j ACCEPT
    check_status "Adding Kubernetes API rule"
else
    log "Rule for Kubernetes API port 8443 already exists"
fi

# Rule for Portainer NodePort (30778)
if ! sudo iptables -C INPUT -p tcp --dport 30778 -j ACCEPT 2>/dev/null; then
    log "Adding rule for Portainer NodePort 30778"
    sudo iptables -A INPUT -p tcp --dport 30778 -j ACCEPT
    check_status "Adding Portainer NodePort rule"
else
    log "Rule for Portainer NodePort 30778 already exists"
fi

# Rule for Minikube network (172.18.0.0/16)
if ! sudo iptables -C INPUT -s 172.18.0.0/16 -j ACCEPT 2>/dev/null; then
    log "Adding rule for Minikube network 172.18.0.0/16"
    sudo iptables -A INPUT -s 172.18.0.0/16 -j ACCEPT
    check_status "Adding Minikube network rule"
else
    log "Rule for Minikube network 172.18.0.0/16 already exists"
fi

# Save the updated IPTABLES rules
log "Saving updated IPTABLES rules"
sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
check_status "Saving IPTABLES rules"

# Detect system resources
log "Detecting system resources"
AVAILABLE_MEMORY=$(( $(free -m | awk '/^Mem:/{print $2}') - 1024 ))
MINIKUBE_MEMORY=$(( AVAILABLE_MEMORY < MIN_MEMORY_MB ? MIN_MEMORY_MB : AVAILABLE_MEMORY ))
AVAILABLE_CPUS=$(( $(nproc) - 1 ))
MINIKUBE_CPUS=$(( AVAILABLE_CPUS < MIN_CPUS ? MIN_CPUS : AVAILABLE_CPUS ))
AVAILABLE_DISK=$(df -BG /var/lib | awk 'NR==2 {print $4}' | sed 's/G//')
MINIKUBE_DISK="${AVAILABLE_DISK:-$MIN_DISK_GB}g"
log "Setting Minikube: $MINIKUBE_MEMORY MB, $MINIKUBE_CPUS CPUs, $MINIKUBE_DISK disk"

# Verify Docker
log "Verifying Docker"
command -v docker &> /dev/null || { log "ERROR: Docker not installed"; exit 1; }
sudo systemctl restart docker
check_status "Restarting Docker"

# Install Minikube and kubectl
log "Installing Minikube"
curl -Lo "$TEMP_DIR/minikube-linux-amd64" https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
check_status "Downloading Minikube"
sudo install "$TEMP_DIR/minikube-linux-amd64" /usr/local/bin/minikube
check_status "Installing Minikube"
rm "$TEMP_DIR/minikube-linux-amd64"

log "Installing kubectl"
curl -Lo "$TEMP_DIR/kubectl" "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
check_status "Downloading kubectl"
sudo install -o root -g root -m 0755 "$TEMP_DIR/kubectl" /usr/local/bin/kubectl
check_status "Installing kubectl"
rm "$TEMP_DIR/kubectl"

# Clean up existing Minikube
log "Cleaning up existing Minikube instance"
sg docker -c "minikube delete" || true

# Start Minikube
log "Starting Minikube with Docker driver, $MINIKUBE_MEMORY MB, $MINIKUBE_CPUS CPUs, $MINIKUBE_DISK disk"
minikube_start_output=$(sg docker -c "minikube start --driver=docker --subnet=$DOCKER_NETWORK --addons=ingress --cpus=$MINIKUBE_CPUS --memory=$MINIKUBE_MEMORY --disk-size=$MINIKUBE_DISK --wait=false -v=9" 2>&1)
if [ $? -ne 0 ]; then
    log "ERROR: Minikube start with Docker driver failed. Output: $minikube_start_output"
    log "Attempting fallback with 'none' driver"
    minikube_start_output=$(sg docker -c "minikube start --driver=none --addons=ingress --cpus=$MINIKUBE_CPUS --memory=$MINIKUBE_MEMORY --disk-size=$MINIKUBE_DISK --wait=false -v=9" 2>&1)
    if [ $? -ne 0 ]; then
        log "ERROR: Minikube start with 'none' driver also failed. Output: $minikube_start_output"
        exit 1
    fi
fi
echo "$minikube_start_output" | sudo tee -a "$LOG_FILE" > /dev/null
check_status "Starting Minikube"

# Verify Minikube status
log "Verifying Minikube status"
minikube_status=$(minikube status 2>&1)
if ! echo "$minikube_status" | grep -q "host: Running"; then
    log "ERROR: Minikube is not running. Status: $minikube_status"
    exit 1
fi
log "Minikube is running"

# Configure kubeconfig
log "Setting kubeconfig"
kubectl config use-context minikube
kubectl config set-cluster minikube --server=https://$KUBE_SERVER:$KUBERNETES_PORT
check_status "Configuring kubeconfig"

# Deploy Portainer agent
log "Deploying Portainer agent"
curl -Lo "$TEMP_DIR/$PORTAINER_AGENT_YAML" "$PORTAINER_AGENT_URL"
kubectl apply -f "$TEMP_DIR/$PORTAINER_AGENT_YAML"
rm "$TEMP_DIR/$PORTAINER_AGENT_YAML"
check_status "Deploying Portainer agent"

# Verify Portainer agent
log "Verifying Portainer agent deployment"
timeout 2m bash -c "
    until kubectl get pods -n portainer -l app=portainer-agent -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q Running; do
        sleep 5
        log \"Waiting for Portainer agent pod to be Running...\"
    done
" || {
    log "ERROR: Portainer agent pod failed to reach Running state within 2 minutes"
    exit 1
}
log "Portainer agent is running"

# Configure systemd service if not already present
if [ ! -f "$SYSTEMD_SERVICE_FILE" ]; then
    log "Configuring systemd service for Minikube"
    cat << EOF | sudo tee "$SYSTEMD_SERVICE_FILE" > /dev/null
[Unit]
Description=Minikube Kubernetes Cluster
After=network.target docker.service
Requires=docker.service

[Service]
User=$NON_ROOT_USER
Group=docker
ExecStart=/usr/local/bin/minikube start --driver=docker --subnet=$DOCKER_NETWORK --addons=ingress --cpus=$MINIKUBE_CPUS --memory=$MINIKUBE_MEMORY --disk-size=$MINIKUBE_DISK --wait=false
ExecStop=/usr/local/bin/minikube stop
Restart=on-failure
RestartSec=10
Environment="HOME=/home/$NON_ROOT_USER"

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable minikube.service
    check_status "Configuring systemd service"
else
    log "Systemd service already configured"
fi

# Diagnostic tests
log "Running diagnostic tests"

run_test "Check Minikube version" "minikube version"
run_test "Check Minikube status" "minikube status"
run_test "Check kubectl client version" "kubectl version --client"
run_test "Check cluster info" "kubectl cluster-info"
run_test "Check nodes" "kubectl get nodes"
run_test "Check Portainer agent pods" "kubectl get pods -n portainer"
run_test "Check systemd service enabled" "systemctl is-enabled minikube.service"

log "Diagnostic tests completed"

# Final status
log "Minikube installation completed successfully. Check status with 'minikube status'"
echo "============================================================="
echo "Minikube Installation Succeeded!"
echo "Check logs at: $LOG_FILE"
echo "To manage Minikube, use: minikube [start|stop|status]"
echo "============================================================="