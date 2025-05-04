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
    echo "  1. Access the remote Portainer UI"
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
if [ "$KUBE_SERVER_RESOLVED_IP" = "127.0.1.1" ] || [ -z "$KUBE_SERVER_RESOLVED_IP" ]; then
    log "WARNING: $KUBE_SERVER resolves to $KUBE_SERVER_RESOLVED_IP or is unresolvable. It should resolve to $SERVER_IP."
    log "Please update /etc/hosts to include: $SERVER_IP $KUBE_SERVER"
    display_failure_notification "Invalid $KUBE_SERVER resolution"
    exit 1
fi
log "Resolved $KUBE_SERVER to $KUBE_SERVER_RESOLVED_IP"

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
sudo iptables -A INPUT -s "$SERVER_IP" -j ACCEPT -m comment --comment "Local server traffic" | sudo tee -a "$LOG_FILE" > /dev/null
sudo iptables -A INPUT -s 172.18.0.0/16 -j ACCEPT -m comment --comment "Minikube network traffic" | sudo tee -a "$LOG_FILE" > /dev/null
check_status "Configuring mert pod failed to reach Running state within 2 minutes"
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

# Configure systemd service for Minikube auto-start
log "Configuring systemd service for Minikube auto-start"
if [ -f "$SYSTEMD_SERVICE_FILE" ]; then
    log "Systemd service file $SYSTEMD_SERVICE_FILE already exists. Skipping creation."
else
    log "Creating Minikube systemd service file at $SYSTEMD_SERVICE_FILE"
    # Create the systemd service file
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
    check_status "Creating Minikube systemd service file"

    # Set permissions for the service file
    sudo chmod 644 "$SYSTEMD_SERVICE_FILE"
    check_status "Setting permissions for Minikube systemd service file"

    # Reload systemd to recognize the new service
    log "Reloading systemd daemon"
    sudo systemctl daemon-reload
    check_status "Reloading systemd daemon"

    # Enable the service to start on boot
    log "Enabling Minikube service to start on boot"
    sudo systemctl enable minikube.service | sudo tee -a "$LOG_FILE" > /dev/null
    check_status "Enabling Minikube service"

    # Start the service immediately (optional, since Minikube is already started)
    log "Minikube is already running. Systemd service will manage it on next reboot."
fi

# Instructions for Portainer integration
log "Preparing kubeconfig for Portainer integration"
log "To manage the Kubernetes cluster in Portainer:"
log "1. Access the remote Portainer UI"
log "2. Go to 'Environments' > 'Add Environment' > 'Kubernetes'"
log "3. Select 'Import kubeconfig' and upload $HOME/.kube/config"
log "4. For Docker management, add a Docker environment using $KUBE_SERVER"
log "Note: Portainer agent is accessible via $KUBE_SERVER:$PORTAINER_NODEPORT. Check service details with: kubectl get svc -n portainer"

# Display completion instructions
log "Kubernetes cluster installation completed successfully!"
log "Minikube is configured to start automatically after server reboot via systemd."
log "Allocated resources: $MINIKUBE_MEMORY MB RAM, $MINIKUBE_CPUS CPUs, $MINIKUBE_DISK disk"
log "Docker network configured: $DOCKER_NETWORK"
log "Kubernetes API server configured: https://$KUBE_SERVER:$KUBERNETES_PORT"
log "Portainer agent is deployed (or already running) in the 'portainer' namespace, accessible at $KUBE_SERVER:$PORTAINER_NODEPORT"
log "Verify cluster status with: kubectl cluster-info"
log "Check nodes with: kubectl get nodes"
log "Check Portainer agent pods with: kubectl get pods -n portainer"
log "Manage the Minikube service with: sudo systemctl [start|stop|restart|status] minikube.service"
log "Log file: $LOG_FILE"

# Display success notification
display_success_notification

# Ensure log file is readable
sudo chmod 664 "$LOG_FILE"
sudo chown "$NON_ROOT_USER":"$NON_ROOT_USER" "$LOG_FILE"