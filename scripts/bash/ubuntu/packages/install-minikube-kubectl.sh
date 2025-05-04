#!/bin/bash

# Script to install Minikube and kubectl on Ubuntu 24.04, deploying a single-node Kubernetes cluster
# Uses Docker as the container runtime (assumes Docker is pre-installed)
# Configures Docker and Minikube to use a user-specified network (default 172.18.0.0/16)
# Deploys Portainer agent for remote management
# Configures kubeconfig and systemd auto-start

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

# Modify /etc/hosts
log "Modifying /etc/hosts to prioritize $SERVER_IP for $KUBE_SERVER"
sudo sed -i "/$KUBE_SERVER/d" /etc/hosts
sudo sed -i "1i $SERVER_IP $KUBE_SERVER" /etc/hosts
check_status "Modifying /etc/hosts"

# Check sudo and Docker group
log "Checking sudo privileges"
sudo -n true 2>/dev/null || { log "ERROR: No sudo privileges"; exit 1; }
log "Checking Docker group membership"
groups | grep -q docker || { log "ERROR: User not in docker group"; exit 1; }

# Configure Docker network
validate_docker_network "$DOCKER_NETWORK"
log "Configuring Docker network to $DOCKER_NETWORK"
if ! grep -q "\"bip\": \"$DOCKER_BIP\"" /etc/docker/daemon.json 2>/dev/null; then
    sudo mkdir -p /etc/docker
    echo "{\"bip\": \"$DOCKER_BIP\", \"fixed-cidr\": \"$DOCKER_NETWORK\", \"exec-opts\": [\"native.cgroupdriver=systemd\"]}" | sudo tee /etc/docker/daemon.json > /dev/null
    sudo systemctl restart docker
    check_status "Configuring Docker network"
fi

# Verify Docker resources
log "Verifying Docker resources"
DOCKER_INFO=$(docker info --format '{{.MemTotal}} {{.NCPU}}')
DOCKER_MEMORY_MB=$(( $(echo "$DOCKER_INFO" | awk '{print $1}') / 1024 / 1024 ))
DOCKER_CPUS=$(echo "$DOCKER_INFO" | awk '{print $2}')
log "Docker resources: $DOCKER_MEMORY_MB MB memory, $DOCKER_CPUS CPUs"

# Clean up conflicting networks
log "Removing conflicting Docker networks"
docker network ls --filter "driver=bridge" -q | xargs -r docker network rm 2>/dev/null || true

# Configure IPTABLES
log "Configuring IPTABLES rules"
sudo iptables -F
sudo iptables -A INPUT -p tcp --dport "$KUBERNETES_PORT" -j ACCEPT
sudo iptables -A INPUT -p tcp --dport "$PORTAINER_NODEPORT" -j ACCEPT
sudo iptables -A INPUT -s 172.18.0.0/16 -j ACCEPT
sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
check_status "Configuring IPTABLES"

# Detect resources
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
curl -Lo "$TEMP_DIR/minikube" https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
sudo install "$TEMP_DIR/minikube" /usr/local/bin/minikube
rm "$TEMP_DIR/minikube"
log "Installing kubectl"
curl -Lo "$TEMP_DIR/kubectl" "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install "$TEMP_DIR/kubectl" /usr/local/bin/kubectl
rm "$TEMP_DIR/kubectl"

# Clean up existing Minikube
log "Cleaning up existing Minikube instance"
sg docker -c "minikube delete" || true

# Start Minikube
log "Starting Minikube with Docker driver, $MINIKUBE_MEMORY MB, $MINIKUBE_CPUS CPUs, $MINIKUBE_DISK disk"
sg docker -c "minikube start --driver=docker --subnet=$DOCKER_NETWORK --addons=ingress --cpus=$MINIKUBE_CPUS --memory=$MINIKUBE_MEMORY --disk-size=$MINIKUBE_DISK --wait=false -v=9" 2>&1 | sudo tee -a "$LOG_FILE" || {
    log "ERROR: Minikube start with Docker driver failed. Attempting fallback with 'none' driver"
    sg docker -c "minikube start --driver=none --addons=ingress --cpus=$MINIKUBE_CPUS --memory=$MINIKUBE_MEMORY --disk-size=$MINIKUBE_DISK --wait=false -v=9" 2>&1 | sudo tee -a "$LOG_FILE" || {
        log "ERROR: Minikube start with 'none' driver also failed"
        exit 1
    }
}
check_status "Starting Minikube"

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

# Configure systemd
log "Configuring systemd service"
cat << EOF | sudo tee "$SYSTEMD_SERVICE_FILE" > /dev/null
[Unit]
Description=Minikube
After=network.target docker.service
Requires=docker.service

[Service]
User=$NON_ROOT_USER
Group=docker
ExecStart=/usr/local/bin/minikube start --driver=docker --subnet=$DOCKER_NETWORK --addons=ingress --cpus=$MINIKUBE_CPUS --memory=$MINIKUBE_MEMORY --disk-size=$MINIKUBE_DISK --wait=false
ExecStop=/usr/local/bin/minikube stop
Restart=on-failure
Environment="HOME=/home/$NON_ROOT_USER"

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable minikube.service
check_status "Configuring systemd"

# Final status
log "Minikube installation completed. Check status with 'minikube status'"