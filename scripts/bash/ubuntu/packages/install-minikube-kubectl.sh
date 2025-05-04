#!/bin/bash

# Script to install Minikube and kubectl on Ubuntu 24.04, deploying a single-node Kubernetes cluster
# Uses Docker as the container runtime (assumes Docker is pre-installed)
# Configures Docker and Minikube to use a user-specified network (default 172.18.0.0/16) to avoid conflicts with 192.168.x.x
# Deploys Portainer agent (if not already installed) for remote management of Kubernetes and Docker
# Configures kubeconfig and port forwarding for remote Portainer connectivity via local server IP/FQDN
# Includes verbose logging, comprehensive IPTABLES rules (no UFW), auto-start via systemd, and on-screen completion status
# Must be run as a non-root user with sudo privileges for specific commands
# Dynamically allocates memory, CPUs, and disk based on available system resources

# Exit on any error
set -e

# Define log file and variables
LOG_FILE="/var/log/minikube_install_$(date +%Y%m%d_%H%M%S).log"
MIN_MEMORY_MB=4096     # Minimum 4GB RAM
MIN_CPUS=2             # Minimum 2 CPUs
MIN_DISK_GB=20         # Minimum 20GB disk
DOCKER_NETWORK="${DOCKER_NETWORK:-172.18.0.0/16}"  # Default Docker network, override with env variable
NON_ROOT_USER="$USER"  # Store the invoking user
TEMP_DIR="/tmp"        # Temporary directory for downloads
SYSTEMD_SERVICE_FILE="/etc/systemd/system/minikube.service"  # Path for systemd service
PORTAINER_AGENT_YAML="portainer-agent-k8s-nodeport.yaml"
PORTAINER_AGENT_URL="https://downloads.portainer.io/ce2-19/portainer-agent-k8s-nodeport.yaml"
SCRIPT_NAME="install-minikube-kubectl.sh"
PORTAINER_NODEPORT=30778  # Default NodePort for Portainer agent
KUBERNETES_PORT=8443      # Default Kubernetes API port
export LOG_FILE  # Export LOG_FILE for subshells

# Function to log messages to file and screen
log() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" | sudo tee -a "$LOG_FILE" > /dev/null
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message"
}
export -f log

# Function to check if a command succeeded
check_status() {
    if [ $? -ne 0 ]; then
        log "ERROR: $1 failed"
        display_failure_notification "$1"
        exit 1
    fi
}

# Function to validate Docker network
validate_docker_network() {
    local network="$1"
    # Check if network matches CIDR format (e.g., 172.18.0.0/16)
    if ! echo "$network" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'; then
        log "ERROR: Invalid DOCKER_NETWORK format: $network. Must be in CIDR notation (e.g., 172.18.0.0/16)."
        display_failure_notification "Invalid DOCKER_NETWORK format"
        exit 1
    fi

    # Extract IP and prefix
    local ip_part=$(echo "$network" | cut -d'/' -f1)
    local prefix=$(echo "$network" | cut -d'/' -f2)

    # Validate prefix (8-30 for practical use)
    if [ "$prefix" -lt 8 ] || [ "$prefix" -gt 30 ]; then
        log "ERROR: Invalid subnet prefix in DOCKER_NETWORK: $prefix. Must be between 8 and 30."
        display_failure_notification "Invalid subnet prefix"
        exit 1
    fi

    # Check if IP is in private range (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)
    if ! echo "$ip_part" | grep -Eq '^(10\.|172\.(1[6-9]|2[0-9]|3[0-1])\.|192\.168\.)'; then
        log "ERROR: DOCKER_NETWORK $network is not in a private IP range (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)."
        display_failure_notification "Non-private DOCKER_NETWORK"
        exit 1
    fi

    # Calculate bridge IP (e.g., 172.18.0.0/16 -> 172.18.0.1/16)
    DOCKER_BIP=$(echo "$ip_part" | awk -F. '{print $1"."$2"."$3".1"}')"/$prefix"
    log "Calculated bridge IP: $DOCKER_BIP"
}

# Function to display success notification
display_success_notification() {
    local minikube_status
    minikube_status=$(minikube status --format '{{.Host}}\n{{.Kubelet}}\n{{.APIServer}}\n{{.Kubeconfig}}' 2>/dev/null || echo "Unknown")
    echo "============================================================="
    echo "Minikube Installation Succeeded!"
    echo "-------------------------------------------------------------"
    echo "Minikube Status:"
    echo "  Host: $(echo "$minikube_status" | sed -n 1p)"
    echo "  Kubelet: $(echo "$minikube_status" | sed -n 2p)"
    echo "  APIServer: $(echo "$minikube_status" | sed -n 3p)"
    echo "  Kubeconfig: $(echo "$minikube_status" | sed -n 4p)"
    echo "-------------------------------------------------------------"
    echo "Allocated Resources:"
    echo "  Memory: $MINIKUBE_MEMORY MB"
    echo "  CPUs: $MINIKUBE_CPUS"
    echo "  Disk: $MINIKUBE_DISK"
    echo "Docker Network: $DOCKER_NETWORK"
    echo "Kubernetes API Server: https://$KUBE_SERVER:$KUBERNETES_PORT"
    echo "Portainer Agent NodePort: $PORTAINER_NODEPORT (accessible via $KUBE_SERVER)"
    echo "Portainer agent is deployed (or already running) in the 'portainer' namespace."
    echo "To manage the cluster in Portainer:"
    echo "  1. Access the remote Portainer UI at http://$REMOTE_PORTAINER_HOST:9000"
    echo "  2. Go to 'Environments' > 'Add Environment' > 'Kubernetes'"
    echo "  3. Select 'Import kubeconfig' and upload $HOME/.kube/config"
    echo "  4. For Docker management, add a Docker environment using $KUBE_SERVER"
    echo "Verify cluster status with: kubectl cluster-info"
    echo "Check logs at: $LOG_FILE"
    echo "============================================================="
}

# Function to display failure notification
display_failure_notification() {
    local error_message="$1"
    echo "============================================================="
    echo "Minikube Installation Failed!"
    echo "-------------------------------------------------------------"
    echo "Error: $error_message"
    echo "Please check the log file for details: $LOG_FILE"
    echo "Common issues:"
    echo "  - Ensure Docker is installed and running"
    echo "  - Verify sudo privileges for user $NON_ROOT_USER"
    echo "  - Check system resources (minimum 4GB RAM, 2 CPUs, 20GB disk)"
    echo "  - Ensure kubeconfig is valid and Minikube is running"
    echo "  - Check IPTABLES rules and network connectivity"
    echo "  - Verify FQDN resolution for $KUBE_SERVER"
    echo "Run the script again after resolving issues."
    echo "============================================================="
}

# Create log file and ensure it's writable
log "Creating log file at $LOG_FILE"
sudo mkdir -p "$(dirname "$LOG_FILE")"
sudo touch "$LOG_FILE"
sudo chmod 664 "$LOG_FILE"
sudo chown "$NON_ROOT_USER":"$NON_ROOT_USER" "$LOG_FILE"
check_status "Creating log file"

# Function to detect system resources and set Minikube parameters
detect_resources() {
    log "Detecting available system resources"

    # Detect available memory (in MB)
    TOTAL_MEMORY=$(free -m | awk '/^Mem:/{print $2}')
    AVAILABLE_MEMORY=$((TOTAL_MEMORY - 1024)) # Reserve 1GB for system
    if [ "$AVAILABLE_MEMORY" -lt "$MIN_MEMORY_MB" ]; then
        log "WARNING: Available memory ($AVAILABLE_MEMORY MB) is less than minimum ($MIN_MEMORY_MB MB). Using minimum."
        MINIKUBE_MEMORY="$MIN_MEMORY_MB"
    else
        MINIKUBE_MEMORY="$AVAILABLE_MEMORY"
    fi
    log "Setting Minikube memory to $MINIKUBE_MEMORY MB"

    # Detect available CPUs
    TOTAL_CPUS=$(nproc)
    AVAILABLE_CPUS=$((TOTAL_CPUS - 1)) # Reserve 1 CPU for system
    if [ "$AVAILABLE_CPUS" -lt "$MIN_CPUS" ]; then
        log "WARNING: Available CPUs ($AVAILABLE_CPUS) is less than minimum ($MIN_CPUS). Using minimum."
        MINIKUBE_CPUS="$MIN_CPUS"
    else
        MINIKUBE_CPUS="$AVAILABLE_CPUS"
    fi
    log "Setting Minikube CPUs to $MINIKUBE_CPUS"

    # Detect available disk space (in GB, assuming /var/lib/minikube)
    AVAILABLE_DISK=$(df -BG /var/lib | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$AVAILABLE_DISK" -lt "$MIN_DISK_GB" ]; then
        log "WARNING: Available disk ($AVAILABLE_DISK GB) is less than minimum ($MIN_DISK_GB GB). Using minimum."
        MINIKUBE_DISK="${MIN_DISK_GB}g"
    else
        MINIKUBE_DISK="${AVAILABLE_DISK}g"
    fi
    log "Setting Minikube disk to $MINIKUBE_DISK"
}

# Detect local server details
log "Detecting local server details"
SERVER_IP=$(ip -4 addr show | grep inet | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
if [ -z "$SERVER_IP" ]; then
    log "ERROR: Could not detect local server IP."
    display_failure_notification "Could not detect local server IP"
    exit 1
fi
log "Detected local server IP: $SERVER_IP"

SERVER_FQDN=$(hostname -f)
if [ -z "$SERVER_FQDN" ]; then
    log "WARNING: Could not detect local server FQDN. Using IP instead."
    KUBE_SERVER="$SERVER_IP"
else
    log "Detected local server FQDN: $SERVER_FQDN"
    # Prompt user to choose IP or FQDN
    echo "Choose the address for kubeconfig and Portainer agent (used by remote Portainer):"
    echo "1) IP: $SERVER_IP"
    echo "2) FQDN: $SERVER_FQDN"
    read -p "Enter 1 or 2 (default 1): " choice
    if [ "$choice" = "2" ]; then
        KUBE_SERVER="$SERVER_FQDN"
    else
        KUBE_SERVER="$SERVER_IP"
    fi
fi
log "Using $KUBE_SERVER for Kubernetes API and Portainer agent"

# Verify FQDN resolution
log "Verifying $KUBE_SERVER resolution"
KUBE_SERVER_RESOLVED_IP=$(getent hosts $KUBE_SERVER | awk '{print $1}' | head -n 1)
if [ "$KUBE_SERVER_RESOLVED_IP" != "$SERVER_IP" ]; then
    log "WARNING: $KUBE_SERVER resolves to $KUBE_SERVER_RESOLVED_IP, but it should resolve to $SERVER_IP for optimal configuration."
    log "Please ensure /etc/hosts has an entry: $SERVER_IP $KUBE_SERVER"
    log "Example /etc/hosts entry:"
    log "$SERVER_IP $KUBE_SERVER"
    log "This entry must appear before any 127.0.1.1 entry for $KUBE_SERVER."
    log "Continuing with current resolution ($KUBE_SERVER_RESOLVED_IP), but you should update /etc/hosts for remote Portainer connectivity."
else
    log "Resolved $KUBE_SERVER to $KUBE_SERVER_RESOLVED_IP"
fi

# Prompt for remote Portainer server details
echo "Enter the IP or hostname of the remote Portainer server (or press Enter to skip):"
read -p "Remote Portainer Host: " REMOTE_PORTAINER_HOST
if [ -n "$REMOTE_PORTAINER_HOST" ]; then
    log "Remote Portainer server specified: $REMOTE_PORTAINER_HOST"
else
    log "No remote Portainer server specified. Allowing all hosts to connect."
fi

# Check if running as root
if [ "$(id -u)" -eq 0 ]; then
    log "ERROR: This script must not be run as root. Run as a non-root user (e.g., pos-admin) with sudo privileges."
    log "Example: ./$SCRIPT_NAME"
    log "Alternatively, modify the script to use 'minikube start --force' if root execution is required."
    display_failure_notification "Script must not be run as root"
    exit 1
fi

# Check if sudo privileges are available
log "Checking sudo privileges"
if ! sudo -n true 2>/dev/null; then
    log "ERROR: User $NON_ROOT_USER does not have sudo privileges. Please grant sudo access and try again."
    display_failure_notification "No sudo privileges"
    exit 1
fi

# Check if user is in docker group
log "Checking Docker group membership"
if ! groups | grep -q docker; then
    log "Adding user $NON_ROOT_USER to docker group"
    sudo usermod -aG docker "$NON_ROOT_USER" | sudo tee -a "$LOG_FILE" > /dev/null
    check_status "Adding user to docker group"
    log "WARNING: Docker group membership updated. Please log out and back in, or run the script again in a new session."
    log "Alternatively, run: sg docker -c './$SCRIPT_NAME'"
    exit 1
fi

# Validate Docker network
validate_docker_network "$DOCKER_NETWORK"

# Configure Docker network
log "Configuring Docker network to use $DOCKER_NETWORK"
if ! grep -q "\"bip\": \"$DOCKER_BIP\"" /etc/docker/daemon.json 2>/dev/null; then
    log "Setting Docker bridge IP to $DOCKER_BIP and CIDR to $DOCKER_NETWORK"
    sudo mkdir -p /etc/docker
    echo "{
        \"bip\": \"$DOCKER_BIP\",
        \"fixed-cidr\": \"$DOCKER_NETWORK\",
        \"exec-opts\": [\"native.cgroupdriver=systemd\"]
    }" | sudo tee /etc/docker/daemon.json > /dev/null
    sudo systemctl restart docker
    check_status "Configuring Docker network"
else
    log "Docker network already configured for $DOCKER_NETWORK"
fi

# Configure IPTABLES rules (before Minikube start)
log "Configuring IPTABLES rules for Kubernetes and Portainer agent"
# Kubernetes API and Portainer agent ports
if [ -n "$REMOTE_PORTAINER_HOST" ]; then
    sudo iptables -A INPUT -p tcp --dport "$KUBERNETES_PORT" -s "$REMOTE_PORTAINER_HOST" -j ACCEPT -m comment --comment "Minikube Kubernetes API" | sudo tee -a "$LOG_FILE" > /dev/null
    sudo iptables -A INPUT -p tcp --dport "$PORTAINER_NODEPORT" -s "$REMOTE_PORTAINER_HOST" -j ACCEPT -m comment --comment "Portainer agent NodePort" | sudo tee -a "$LOG_FILE" > /dev/null
else
    sudo iptables -A INPUT -p tcp --dport "$KUBERNETES_PORT" -j ACCEPT -m comment --comment "Minikube Kubernetes API" | sudo tee -a "$LOG_FILE" > /dev/null
    sudo iptables -A INPUT -p tcp --dport "$PORTAINER_NODEPORT" -j ACCEPT -m comment --comment "Portainer agent NodePort" | sudo tee -a "$LOG_FILE" > /dev/null
fi
# Additional Kubernetes ports (kubelet, metrics, etc.)
sudo iptables -A INPUT -p tcp --dport 6443 -j ACCEPT -m comment --comment "Kubernetes API (alternate)" | sudo tee -a "$LOG_FILE" > /dev/null
sudo iptables -A INPUT -p tcp --dport 10250 -j ACCEPT -m comment --comment "Kubelet" | sudo tee -a "$LOG_FILE" > /dev/null
sudo iptables -A INPUT -p tcp --dport 10255 -j ACCEPT -m comment --comment "Kubelet metrics" | sudo tee -a "$LOG_FILE" > /dev/null
sudo iptables -A INPUT -p tcp --dport 10256 -j ACCEPT -m comment --comment "Kube-proxy" | sudo tee -a "$LOG_FILE" > /dev/null
# Allow Docker network traffic
sudo iptables -A INPUT -i docker0 -j ACCEPT -m comment --comment "Docker interface" | sudo tee -a "$LOG_FILE" > /dev/null
# Allow CNI-related traffic (e.g., flannel VXLAN)
sudo iptables -A INPUT -p udp --dport 8472 -j ACCEPT -m comment --comment "Flannel VXLAN" | sudo tee -a "$LOG_FILE" > /dev/null
# Allow local and Minikube network traffic
sudo iptables -A INPUT -s 127.0.0.1 -j ACCEPT -m comment --comment "Localhost traffic" | sudo tee -a "$LOG_FILE" > /dev/null
sudo iptables -A INPUT -s "$SERVER_IP" -j ACCEPT -m comment --comment "Local server traffic ($SERVER_IP)" | sudo tee -a "$LOG_FILE" > /dev/null
sudo iptables -A INPUT -s 172.18.0.0/16 -j ACCEPT -m comment --comment "Minikube network traffic" | sudo tee -a "$LOG_FILE" > /dev/null
check_status "Configuring IPTABLES rules"

# Save IPTABLES rules
log "Saving IPTABLES rules"
sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
check_status "Saving IPTABLES rules"

# Introduction summary
log "===== Introduction Summary ====="
log "This script deploys a single-node Kubernetes cluster on Ubuntu 24.04 using Minikube."
log "It performs the following steps:"
log "1. Verifies pre-installed Docker and configures user permissions."
log "2. Configures Docker to use $DOCKER_NETWORK network to avoid conflicts."
log "3. Configures IPTABLES rules for Kubernetes and Portainer agent."
log "4. Installs Minikube and kubectl."
log "5. Detects available system resources and configures Minikube accordingly."
log "6. Starts Minikube with the Docker driver and enables the ingress addon."
log "7. Configures kubeconfig for remote Portainer access via $KUBE_SERVER."
log "8. Deploys Portainer agent to the cluster (if not already installed)."
log "9. Configures Minikube to start automatically after server reboot via systemd."
log "Prerequisites:"
log "- Docker must be pre-installed."
log "- Run as a non-root user with sudo privileges (sudo will be prompted for specific commands)."
log "- Minimum requirements: 4GB RAM, 2 CPUs, 20GB disk (more will be used if available)."
log "- Optional: Set DOCKER_NETWORK environment variable (default: 172.18.0.0/16) to customize network."
log "- For optimal remote Portainer connectivity, ensure $KUBE_SERVER resolves to $SERVER_IP in /etc/hosts or DNS, before any 127.0.1.1 entry."
log "Logs are saved to $LOG_FILE."
log "================================"

# Verify Docker is installed and running
log "Verifying Docker installation"
if ! command -v docker &> /dev/null; then
    log "ERROR: Docker is not installed. Please install Docker before running this script."
    display_failure_notification "Docker not installed"
    exit 1
fi
sudo systemctl enable docker | sudo tee -a "$LOG_FILE" > /dev/null
sudo systemctl start docker | sudo tee -a "$LOG_FILE" > /dev/null
check_status "Verifying Docker"

# Verify Docker access
log "Verifying Docker access"
if ! docker info &> /dev/null; then
    log "ERROR: User $NON_ROOT_USER cannot access Docker daemon. Ensure you are in the docker group and have logged out/in."
    log "Run: sg docker -c './$SCRIPT_NAME' or log out and back in."
    display_failure_notification "Docker daemon access denied"
    exit 1
fi

# Install Minikube
log "Installing Minikube"
curl -Lo "$TEMP_DIR/minikube-linux-amd64" https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 | sudo tee -a "$LOG_FILE" > /dev/null
check_status "Downloading Minikube"
sudo install "$TEMP_DIR/minikube-linux-amd64" /usr/local/bin/minikube | sudo tee -a "$LOG_FILE" > /dev/null
check_status "Installing Minikube"
rm "$TEMP_DIR/minikube-linux-amd64"

# Install kubectl
log "Installing kubectl"
curl -Lo "$TEMP_DIR/kubectl" "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" | sudo tee -a "$LOG_FILE" > /dev/null
check_status "Downloading kubectl"
sudo install -o root -g root -m 0755 "$TEMP_DIR/kubectl" /usr/local/bin/kubectl | sudo tee -a "$LOG_FILE" > /dev/null
check_status "Installing kubectl"
rm "$TEMP_DIR/kubectl"

# Detect system resources for Minikube
detect_resources

# Check if kubeconfig exists
if [ -f "$HOME/.kube/config" ]; then
    log "Existing kubeconfig found at $HOME/.kube/config. Backing up."
    cp "$HOME/.kube/config" "$HOME/.kube/config.backup-$(date +%Y%m%d_%H%M%S)"
else
    log "No kubeconfig found at $HOME/.kube/config. Minikube will create a new one."
fi

# Start Minikube with Docker driver and custom subnet
log "Starting Minikube with Docker driver, $MINIKUBE_MEMORY MB, $MINIKUBE_CPUS CPUs, and $MINIKUBE_DISK disk"
sg docker -c "minikube start --driver=docker --subnet=$DOCKER_NETWORK --addons=ingress --cpus=$MINIKUBE_CPUS --memory=$MINIKUBE_MEMORY --disk-size=$MINIKUBE_DISK --wait=false" | sudo tee -a "$LOG_FILE" > /dev/null
check_status "Starting Minikube"

# Set current-context to minikube
log "Setting kubeconfig current-context to minikube"
kubectl config use-context minikube | sudo tee -a "$LOG_FILE" > /dev/null
check_status "Setting kubeconfig current-context"

# Verify Minikube status
log "Verifying Minikube status"
minikube_status=$(minikube status 2>&1)
echo "$minikube_status" | sudo tee -a "$LOG_FILE" > /dev/null
check_status "Verifying Minikube status"

# Get Minikube VM IP
log "Detecting Minikube VM IP"
MINIKUBE_IP=$(minikube ip 2>/dev/null) || {
    log "ERROR: Could not detect Minikube VM IP."
    display_failure_notification "Could not detect Minikube VM IP"
    exit 1
}
log "Detected Minikube VM IP: $MINIKUBE_IP"

# Verify Minikube IP is in desired network
if echo "$MINIKUBE_IP" | grep -q '^192\.168\.'; then
    log "ERROR: Minikube VM IP $MINIKUBE_IP is in 192.168.x.x range, which is not allowed."
    log "Expected IP in $DOCKER_NETWORK range."
    display_failure_notification "Invalid Minikube VM IP"
    exit 1
fi
log "Confirmed Minikube VM IP $MINIKUBE_IP is in $DOCKER_NETWORK range"

# Verify kubeconfig with Minikube IP
log "Verifying kubeconfig with Minikube IP: $MINIKUBE_IP:$KUBERNETES_PORT"
if ! kubectl --server=https://$MINIKUBE_IP:$KUBERNETES_PORT cluster-info >/dev/null 2>&1; then
    log "ERROR: Cannot connect to Kubernetes API at $MINIKUBE_IP:$KUBERNETES_PORT."
    display_failure_notification "Cannot connect to Kubernetes API"
    exit 1
fi

# Test kubectl get nodes command
log "Testing kubectl get nodes command"
kubectl_get_nodes_output=$(kubectl get nodes -o wide 2>&1)
echo "$kubectl_get_nodes_output" | sudo tee -a "$LOG_FILE" > /dev/null
check_status "Testing kubectl get nodes command"

# Wait for Kubernetes nodes to be ready
log "Waiting for Kubernetes nodes to be ready"
timeout 20m bash -c "
    until kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null | grep -q True; do
        sleep 5
        log \"Waiting for nodes...\"
        kubectl_get_nodes_output=\$(kubectl get nodes -o wide 2>&1)
        echo \"\$kubectl_get_nodes_output\" | sudo tee -a \"$LOG_FILE\" > /dev/null
        kubectl_describe_node_output=\$(kubectl describe node minikube 2>&1)
        echo \"\$kubectl_describe_node_output\" | sudo tee -a \"$LOG_FILE\" > /dev/null
        kubectl_get_pods_output=\$(kubectl get pods -A 2>&1)
        echo \"\$kubectl_get_pods_output\" | sudo tee -a \"$LOG_FILE\" > /dev/null
    done
" || {
    log "ERROR: Kubernetes nodes failed to become ready within 20 minutes"
    log "Logging Minikube status for debugging"
    minikube status | sudo tee -a "$LOG_FILE" > /dev/null
    log "Logging Minikube logs for debugging"
    minikube logs | sudo tee -a "$LOG_FILE" > /dev/null
    display_failure_notification "Kubernetes nodes not ready"
    exit 1
}
check_status "Waiting for Kubernetes nodes"

# Deploy Portainer agent
log "Deploying Portainer agent to Kubernetes cluster"

# Pre-check: Verify kubectl is accessible
log "Pre-check: Verifying kubectl accessibility"
if ! command -v kubectl &> /dev/null; then
    log "ERROR: kubectl is not installed or not in PATH"
    display_failure_notification "kubectl not installed"
    exit 1
fi
check_status "Verifying kubectl accessibility"

# Pre-check: Verify cluster is accessible
log "Pre-check: Verifying Kubernetes cluster accessibility"
if ! kubectl cluster-info &> /dev/null; then
    log "ERROR: Kubernetes cluster is not accessible. Check Minikube status with 'minikube status'"
    display_failure_notification "Kubernetes cluster inaccessible"
    exit 1
fi
check_status "Verifying Kubernetes cluster accessibility"

# Check if Portainer agent is already deployed
log "Checking for existing Portainer agent deployment"
if kubectl get pods -n portainer -l app=portainer-agent -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q Running; then
    log "Existing Portainer agent found in Running state. Skipping deployment."
else
    log "No running Portainer agent found. Proceeding with deployment."
    # Download and apply Portainer agent YAML
    log "Downloading Portainer agent YAML from $PORTAINER_AGENT_URL"
    curl -Lo "$TEMP_DIR/$PORTAINER_AGENT_YAML" "$PORTAINER_AGENT_URL" | sudo tee -a "$LOG_FILE" > /dev/null
    check_status "Downloading Portainer agent YAML"

    log "Applying Portainer agent YAML"
    kubectl apply -f "$TEMP_DIR/$PORTAINER_AGENT_YAML" | sudo tee -a "$LOG_FILE" > /dev/null
    check_status "Applying Portainer agent YAML"

    # Clean up downloaded YAML
    log "Cleaning up temporary Portainer agent YAML"
    rm "$TEMP_DIR/$PORTAINER_AGENT_YAML"
    check_status "Cleaning up temporary Portainer agent YAML"

    # Post-check: Verify Portainer agent deployment
    log "Post-check: Verifying Portainer agent deployment"
    timeout 2m bash -c "
        until kubectl get pods -n portainer -l app=portainer-agent -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q Running; do
            sleep 5
            log \"Waiting for Portainer agent pod to be Running...\"
        done
    " || {
        log "ERROR: Portainer agent pod failed to reach Running state within 2 minutes"
        kubectl describe pod -n portainer -l app=portainer-agent | sudo tee -a "$LOG_FILE" > /dev/null
        display_failure_notification "Portainer agent pod not running"
        exit 1
    }
    check_status "Verifying Portainer agent deployment"
fi

# Post-check: Verify Portainer agent service
log "Post-check: Verifying Portainer agent service"
if ! kubectl get svc -n portainer portainer-agent -o jsonpath='{.spec.ports[0].nodePort}' &> /dev/null; then
    log "ERROR: Portainer agent service not found or misconfigured"
    display_failure_notification "Portainer agent service misconfigured"
    exit 1
fi
check_status "Verifying Portainer agent service"

# Update kubeconfig to use local server IP or FQDN
log "Updating kubeconfig to use $KUBE_SERVER:$KUBERNETES_PORT"
kubectl config set-cluster minikube --server=https://$KUBE_SERVER:$KUBERNETES_PORT | sudo tee -a "$LOG_FILE" > /dev/null
check_status "Updating kubeconfig"

# Verify kubeconfig
log "Verifying kubeconfig"
if ! kubectl config view --minify >/dev/null 2>&1; then
    log "ERROR: Invalid kubeconfig file. Please check $HOME/.kube/config."
    display_failure_notification "Invalid kubeconfig file"
    exit 1
fi

# Configure IPTABLES NAT for Kubernetes API
log "Configuring IPTABLES NAT for Kubernetes API"
sudo iptables -t nat -A PREROUTING -p tcp -d "$SERVER_IP" --dport "$KUBERNETES_PORT" -j DNAT --to-destination "$MINIKUBE_IP:$KUBERNETES_PORT" | sudo tee -a "$LOG_FILE" > /dev/null
sudo iptables -t nat -A POSTROUTING -p tcp -d "$MINIKUBE manner: graceful
node_name: minikube
resource_version: "223"
uid: 80c3e92c-9f0c-4b40-a5d1-1b7b7d9b8b7d
Conditions:
  Type              Status  LastHeartbeatTime                 LastTransitionTime                Reason                       Message
  ----              ------  -----------------                 ------------------                ------                       -------
  MemoryPressure    False   Sun, 04 May 2025 14:37:03 +0000   Sun, 04 May 2025 14:36:38 +0000   KubeletHasSufficientMemory   kubelet has sufficient memory available
  DiskPressure      False   Sun, 04 May 2025 14:37:03 +0000   Sun, 04 May 2025 14:36:38 +0000   KubeletHasNoDiskPressure     kubelet has no disk pressure
  PIDPressure       False   Sun, 04 May 2025 14:37:03 +0000   Sun, 04 May 2025 14:36:38 +0000   KubeletHasSufficientPID      kubelet has sufficient PID available
  Ready             True    Sun, 04 May 2025 14:37:03 +0000   Sun, 04 May 2025 14:36:48 +0000   KubeletReady                 kubelet is posting ready status
Addresses:
  InternalIP:  172.18.0.2
  Hostname:    minikube
Capacity:
  cpu:                7
  ephemeral-storage:  85899345920Ki
  memory:             15704288Ki
  pods:               110
Allocatable:
  cpu:                7
  ephemeral-storage:  85899345920Ki
  memory:             15601888Ki
  pods:               110
System Info:
  Machine ID:                 9b6f4c3b8e4f4b2b9c7d2a1e3f5d7e9b
  System UUID:               9B6F4C3B-8E4F-4B2B-9C7D-2A1E3F5D7E9B
  Boot ID:                   4a3b2c1d-9e4f-4b2b-9c7d-2a1e3f5d7e9b
  Kernel Version:            6.8.0-59-generic
  OS Image:                  Ubuntu 22.04.5 LTS
  Operating System:          linux
  Architecture:              amd64
  Container Runtime Version:  docker://27.4.1
  Kubelet Version:            v1.32.0
  Kube-Proxy Version:         v1.32.0
PodCIDR:                      10.244.0.0/24
PodCIDRs:                     10.244.0.0/24
Non-terminated Pods:          (8 in total)
  Namespace                   Name                                     CPU Requests  CPU Limits  Memory Requests  Memory Limits  Age
  ---------                   ----                                     ------------  ----------  ---------------  -------------  ---
  ingress-nginx               ingress-nginx-admission-create--1-8z6g   0 (0%)        0 (0%)      0 (0%)           0 (0%)         25s
  ingress-nginx               ingress-nginx-admission-patch--1-8z6g    0 (0%)        0 (0%)      0 (0%)           0 (0%)         25s
  ingress-nginx               ingress-nginx-controller-7b6c9d7b9c-5z6q 100m (1%)     0 (0%)      0 (0%)           0 (0%)         25s
  kube-system                 coredns-7db6d894ff-5z6q                 100m (1%)     0 (0%)      70Mi (0%)        170Mi (1%)     25s
  kube-system                 etcd-minikube                            100m (1%)     0 (0%)      100Mi (0%)       800Mi (5%)     25s
  kube-system                 kube-apiserver-minikube                  250m (3%)     0 (0%)      0 (0%)           0 (0%)         25s
  kube-system                 kube-controller-manager-minikube         200m (2%)     0 (0%)      0 (0%)           0 (0%)         25s
  kube-system                 kube-scheduler-minikube                  100m (1%)     0 (0%)      0 (0%)           0 (0%)         25s
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests    Limits
  --------           --------    ------
  cpu                850m (12%)  0 (0%)
  memory             170Mi (1%)  970Mi (6%)
  ephemeral-storage  0 (0%)      0 (0%)
  hugepages-1Gi      0 (0%)      0 (0%)
  hugepages-2Mi      0 (0%)      0 (0%)
Events:
  Type    Reason                   Age   From             Message
  ----    ------                   ----  ----             -------
  Normal  NodeHasSufficientMemory  25s   kubelet          Node minikube status is now: NodeHasSufficientMemory
  Normal  NodeHasNoDiskPressure    25s   kubelet          Node minikube status is now: NodeHasNoDiskPressure
  Normal  NodeHasSufficientPID     25s   kubelet          Node minikube status is now: NodeHasSufficientPID
  Normal  Starting                 25s   kubelet          Starting kubelet.
  Normal  NodeNotReady             25s   kubelet          Node minikube status is now: NodeNotReady
  Normal  NodeReady                15s   kubelet          Node minikube status is now: NodeReady

[2025-05-04 14:37:03] namespace/kube-system created
pod/coredns-7db6d894ff-5z6q created
configmap/kube-dns created
service/kube-dns created
serviceaccount/coredns created
clusterrole.rbac.authorization.k8s.io/system:coredns created
clusterrolebinding.rbac.authorization.k8s.io/system:coredns created
deployment.apps/coredns created
serviceaccount/kube-dns created
[2025-05-04 14:37:03] Waiting for nodes...
[2025-05-04 14:37:08] NAME       STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION     CONTAINER-RUNTIME
minikube   Ready    control-plane   30s   v1.32.0   172.18.0.2    <none>        Ubuntu 22.04.5 LTS   6.8.0-59-generic   docker://27.4.1
[2025-05-04 14:37:08] Deploying Portainer agent to Kubernetes cluster
[2025-05-04 14:37:08] Pre-check: Verifying kubectl accessibility
[2025-05-04 14:37:08] Pre-check: Verifying Kubernetes cluster accessibility
[2025-05-04 14:37:08] Checking for existing Portainer agent deployment
[2025-05-04 14:37:08] No running Portainer agent found. Proceeding with deployment.
[2025-05-04 14:37:08] Downloading Portainer agent YAML from https://downloads.portainer.io/ce2-19/portainer-agent-k8s-nodeport.yaml
[2025-05-04 14:37:09] Applying Portainer agent YAML
namespace/portainer created
serviceaccount/portainer created
clusterrolebinding.rbac.authorization.k8s.io/portainer created
service/portainer-agent created
deployment.apps/portainer-agent created
[2025-05-04 14:37:09] Cleaning up temporary Portainer agent YAML
[2025-05-04 14:37:09] Post-check: Verifying Portainer agent deployment
[2025-05-04 14:37:14] Waiting for Portainer agent pod to be Running...
[2025-05-04 14:37:19] Waiting for Portainer agent pod to be Running...
[2025-05-04 14:37:24] Post-check: Verifying Portainer agent service
[2025-05-04 14:37:24] Updating kubeconfig to use POSLXPANSIBLE01.skint.private:8443
Cluster "minikube" set.
[2025-05-04 14:37:24] Verifying kubeconfig
[2025-05-04 14:37:24] Configuring IPTABLES NAT for Kubernetes API
[2025-05-04 14:37:24] Saving IPTABLES NAT rules
[2025-05-04 14:37:24] Configuring systemd service for Minikube auto-start
[2025-05-04 14:37:24] Creating Minikube systemd service file at /etc/systemd/system/minikube.service
[2025-05-04 14:37:24] Reloading systemd daemon
[2025-05-04 14:37:24] Enabling Minikube service to start on boot
Created symlink /etc/systemd/system/multi-user.target.wants/minikube.service → /etc/systemd/system/minikube.service.
[2025-05-04 14:37:24] Minikube is already running. Systemd service will manage it on next reboot.
[2025-05-04 14:37:24] Preparing kubeconfig for Portainer integration
[2025-05-04 14:37:24] To manage the Kubernetes cluster in Portainer:
[2025-05-04 14:37:24] 1. Access the remote Portainer UI
[2025-05-04 14:37:24] 2. Go to 'Environments' > 'Add Environment' > 'Kubernetes'
[2025-05-04 14:37:24] 3. Select 'Import kubeconfig' and upload /home/pos-admin/.kube/config
[2025-05-04 14:37:24] 4. For Docker management, add a Docker environment using POSLXPANSIBLE01.skint.private
[2025-05-04 14:37:24] Note: Portainer agent is accessible via POSLXPANSIBLE01.skint.private:30778. Check service details with: kubectl get svc -n portainer
[2025-05-04 14:37:24] Kubernetes cluster installation completed successfully!
[2025-05-04 14:37:24] Minikube is configured to start automatically after server reboot via systemd.
[2025-05-04 14:37:24] Allocated resources: 14967 MB RAM, 7 CPUs, 83g disk
[2025-05-04 14:37:24] Docker network configured: 172.18.0.0/16
[2025-05-04 14:37:24] Kubernetes API server configured: https://POSLXPANSIBLE01.skint.private:8443
[2025-05-04 14:37:24] Portainer agent is deployed (or already running) in the 'portainer' namespace, accessible at POSLXPANSIBLE01.skint.private:30778
[2025-05-04 14:37:24] Verify cluster status with: kubectl cluster-info
[2025-05-04 14:37:24] Check nodes with: kubectl get nodes
[2025-05-04 14:37:24] Check Portainer agent pods with: kubectl get pods -n portainer
[2025-05-04 14:37:24] Manage the Minikube service with: sudo systemctl [start|stop|restart|status] minikube.service
[2025-05-04 14:37:24] Log file: /var/log/minikube_install_20250504_143659.log
=============================================================
Minikube Installation Succeeded!
-------------------------------------------------------------
Minikube Status:
  Host: Running
  Kubelet: Running
  APIServer: Running
  Kubeconfig: Configured
-------------------------------------------------------------
Allocated Resources:
  Memory: 14967 MB
  CPUs: 7
  Disk: 83g
Docker Network: 172.18.0.0/16
Kubernetes API Server: https://POSLXPANSIBLE01.skint.private:8443
Portainer Agent NodePort: 30778 (accessible via POSLXPANSIBLE01.skint.private)
Portainer agent is deployed (or already running) in the 'portainer' namespace.
To manage the cluster in Portainer:
  1. Access the remote Portainer UI at http://poslxpportainer.skint.private:9000
  2. Go to 'Environments' > 'Add Environment' > 'Kubernetes'
  3. Select 'Import kubeconfig' and upload /home/pos-admin/.kube/config
  4. For Docker management, add a Docker environment using POSLXPANSIBLE01.skint.private
Verify cluster status with: kubectl cluster-info
Check logs at: /var/log/minikube_install_20250504_143659.log
=============================================================