#!/bin/bash

# Script to install Minikube and kubectl on Ubuntu 24.04, deploying a single-node Kubernetes cluster
# Uses Docker as the container runtime (assumes Docker is pre-installed)
# Deploys Portainer agent (if not already installed) and prepares cluster for management in Portainer
# Includes verbose logging, error handling, IPTABLES rules, auto-start via systemd, and on-screen completion status
# Must be run as a non-root user with sudo privileges for specific commands
# Dynamically allocates memory, CPUs, and disk based on available system resources

# Exit on any error
set -e

# Define log file and variables
LOG_FILE="/var/log/minikube_install_$(date +%Y%m%d_%H%M%S).log"
MIN_MEMORY_MB=4096     # Minimum 4GB RAM
MIN_CPUS=2             # Minimum 2 CPUs
MIN_DISK_GB=20         # Minimum 20GB disk
NON_ROOT_USER="$USER"  # Store the invoking user
TEMP_DIR="/tmp"        # Temporary directory for downloads
SYSTEMD_SERVICE_FILE="/etc/systemd/system/minikube.service"  # Path for systemd service
PORTAINER_AGENT_YAML="portainer-agent-k8s-nodeport.yaml"
PORTAINER_AGENT_URL="https://downloads.portainer.io/ce2-19/portainer-agent-k8s-nodeport.yaml"
SCRIPT_NAME="install-minikube-kubectl.sh"

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
    echo "Portainer agent is deployed (or already running) in the 'portainer' namespace."
    echo "To manage the cluster in Portainer:"
    echo "  1. Access Portainer UI (e.g., http://$SERVER_IP:9000)"
    echo "  2. Go to 'Environments' > 'Add Environment' > 'Kubernetes'"
    echo "  3. Upload kubeconfig from $HOME/.kube/config"
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

# Introduction summary
log "===== Introduction Summary ====="
log "This script deploys a single-node Kubernetes cluster on Ubuntu 24.04 using Minikube."
log "It performs the following steps:"
log "1. Verifies pre-installed Docker and configures user permissions."
log "2. Installs Minikube and kubectl."
log "3. Detects available system resources and configures Minikube accordingly."
log "4. Starts Minikube with the Docker driver and enables the ingress addon."
log "5. Configures IPTABLES rules for Kubernetes and Docker."
log "6. Deploys Portainer agent to the cluster (if not already installed)."
log "7. Prepares kubeconfig for Portainer management."
log "8. Configures Minikube to start automatically after server reboot via systemd."
log "Prerequisites:"
log "- Docker must be pre-installed."
log "- Run as a non-root user with sudo privileges (sudo will be prompted for specific commands)."
log "- Minimum requirements: 4GB RAM, 2 CPUs, 20GB disk (more will be used if available)."
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

# Verify Docker CRI compatibility
log "Verifying Docker CRI compatibility"
if ! sudo docker info --format '{{.CgroupDriver}}' | grep -q "systemd"; then
    log "Configuring Docker to use systemd cgroup driver"
    sudo mkdir -p /etc/docker
    echo '{"exec-opts": ["native.cgroupdriver=systemd"]}' | sudo tee /etc/docker/daemon.json > /dev/null
    sudo systemctl restart docker
    check_status "Configuring Docker cgroup driver"
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

# Start Minikube with Docker driver in the docker group context
log "Starting Minikube with Docker driver, $MINIKUBE_MEMORY MB, $MINIKUBE_CPUS CPUs, and $MINIKUBE_DISK disk"
sg docker -c "minikube start --driver=docker --addons=ingress --cpus=$MINIKUBE_CPUS --memory=$MINIKUBE_MEMORY --disk-size=$MINIKUBE_DISK --wait=false" | sudo tee -a "$LOG_FILE" > /dev/null
check_status "Starting Minikube"

# Verify Minikube status
log "Verifying Minikube status"
minikube status | sudo tee -a "$LOG_FILE" > /dev/null
check_status "Verifying Minikube status"

# Get the Kubernetes API port dynamically
KUBERNETES_PORT=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' | grep -o '[0-9]\+$') || {
    log "WARNING: Could not detect Kubernetes API port, defaulting to 8443"
    KUBERNETES_PORT="8443"
}
log "Detected Kubernetes API port: $KUBERNETES_PORT"

# Wait for Kubernetes nodes to be ready
log "Waiting for Kubernetes nodes to be ready"
timeout 5m bash -c "
    until kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null | grep -q True; do
        sleep 5
        log \"Waiting for nodes...\"
    done
" || {
    log "ERROR: Kubernetes nodes failed to become ready within 5 minutes"
    display_failure_notification "Kubernetes nodes not ready"
    exit 1
}
check_status "Waiting for Kubernetes nodes"

# Configure IPTABLES rules (append to existing rules)
log "Configuring IPTABLES rules for Kubernetes"
sudo iptables -A INPUT -p tcp --dport "$KUBERNETES_PORT" -j ACCEPT -m comment --comment "Minikube Kubernetes API" | sudo tee -a "$LOG_FILE" > /dev/null
sudo iptables -A INPUT -i docker0 -j ACCEPT -m comment --comment "Docker interface" | sudo tee -a "$LOG_FILE" > /dev/null
check_status "Configuring IPTABLES rules"

# Save IPTABLES rules
log "Saving IPTABLES rules"
sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
check_status "Saving IPTABLES rules"

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
    check_status "Cleaning up Portainer agent YAML"

    # Post-check: Verify Portainer agent deployment
    log "Post-check: Verifying Portainer agent deployment"
    timeout 2m bash -c "
        until kubectl get pods -n portainer -l app=portainer-agent -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q Running; do
            sleep 5
            log \"Waiting for Portainer agent pod to be Running...\"
        done
    " || {
        log "ERROR: Portainer agent pod failed to reach Running state within 2 minutes"
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
ExecStart=/usr/local/bin/minikube start --driver=docker --addons=ingress --cpus=$MINIKUBE_CPUS --memory=$MINIKUBE_MEMORY --disk-size=$MINIKUBE_DISK --wait=false
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
log "1. Access Portainer UI (e.g., http://$SERVER_IP:9000)"
log "2. Go to 'Environments' > 'Add Environment' > 'Kubernetes'"
log "3. Select 'Local Kubernetes' or 'Import kubeconfig'"
log "4. Upload or copy the kubeconfig from $HOME/.kube/config (created by Minikube)"
log "5. Save and connect to manage the cluster"
log "Note: Portainer agent is deployed and accessible via NodePort. Check service details with: kubectl get svc -n portainer"

# Display completion instructions
SERVER_IP=$(ip -4 addr show | grep inet | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -n 1)
log "Kubernetes cluster installation completed successfully!"
log "Minikube is configured to start automatically after server reboot via systemd."
log "Allocated resources: $MINIKUBE_MEMORY MB RAM, $MINIKUBE_CPUS CPUs, $MINIKUBE_DISK disk"
log "Portainer agent is deployed (or already running) in the 'portainer' namespace."
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