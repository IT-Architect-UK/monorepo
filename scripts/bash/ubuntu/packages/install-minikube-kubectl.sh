#!/bin/bash

# Script to install Minikube and kubectl on Ubuntu 24.04, deploying a single-node Kubernetes cluster
# Uses Docker as the container runtime (assumes Docker is pre-installed)
# Configures Docker and Minikube to use a user-specified network (default 172.18.0.0/16)
# Deploys Portainer agent for remote management
# Configures kubeconfig and systemd auto-start
# Preserves existing IPTABLES rules and adds only necessary new rules
# Includes diagnostic tests and Portainer Agent connection instructions for CE

# Exit on any error
set -e

# Function to validate Docker network format and calculate bridge IP
validate_docker_network() {
    local network="$1"
    if ! echo "$network" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'; then
        log "ERROR: Invalid DOCKER_NETWORK format: $network"
        exit 1
    fi
    DOCKER_BIP=$(echo "$network" | awk -F'/' '{split($1,a,"."); print a[1]"."a[2]"."a[3]".1/"$2}')
    log "Calculated bridge IP: $DOCKER_BIP"
}

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
KUBECONFIG="$HOME/.kube/config"
export LOG_FILE
export KUBECONFIG

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
    echo "$description: $result" >> /tmp/diagnostic_results.txt
}

# Display diagnostic summary
display_diagnostic_summary() {
    log "Displaying diagnostic summary"
    echo "============================================================="
    echo "Diagnostic Test Summary"
    echo "============================================================="
    cat /tmp/diagnostic_results.txt
    echo "============================================================="
    log "Diagnostic summary displayed"
    rm -f /tmp/diagnostic_results.txt
}

# Display Portainer connection instructions
display_portainer_instructions() {
    local instructions="
=============================================================
Portainer Agent Connection Instructions (Portainer CE)
=============================================================
You are using the Portainer Community Edition with the Agent option.
To connect Portainer to this Minikube cluster:

1. Ensure the Portainer agent is deployed:
   - The script has already applied the agent YAML: $PORTAINER_AGENT_URL
   - Verify the agent pod is running on this server:
     kubectl get pods -n portainer
   - Expected output: A pod named 'portainer-agent-...' in 'Running' state
   - Verify the agent service:
     kubectl get svc -n portainer
   - Expected output: A service named 'portainer-agent' with NodePort 30778

2. Configure Portainer on the Portainer server (e.g., 192.168.4.109):
   - Access the Portainer UI (e.g., http://192.168.4.109:9000)
   - Go to 'Environments' > 'Add Environment' > 'Kubernetes via Agent'
   - Enter the following details:
     - **Name**: A name for the environment (e.g., 'Minikube')
     - **Environment address**: $KUBE_SERVER:$PORTAINER_NODEPORT (e.g., poslxpansible01.skint.private:30778)
   - Click 'Connect'
   - Note: The Portainer agent uses port 30778, not 9001 or 9000 (which is for the Portainer UI)

3. Verify connectivity from the Portainer server:
   - Test the Portainer agent endpoint:
     curl http://$KUBE_SERVER:$PORTAINER_NODEPORT
   - Expected response: A basic HTTP response or JSON indicating the agent is running
   - Test the Kubernetes API (optional, for debugging):
     curl -k https://$KUBE_SERVER:$KUBERNETES_PORT
   - Expected response: A JSON object with a 403 Forbidden error (indicating the API is reachable but requires authentication)

4. If connection fails:
   - Ensure the agent pod and service are running (see step 1)
   - Verify network connectivity from the Portainer server (192.168.4.109) to $KUBE_SERVER:$PORTAINER_NODEPORT
   - Check IPTABLES NAT rules on this server:
     sudo iptables -t nat -L -v -n
   - Look for entries forwarding 192.168.4.110:8443 to $MINIKUBE_IP:8443
   - Check the Minikube VM IP ($MINIKUBE_IP) is reachable:
     ping $MINIKUBE_IP
   - Check the log file for errors: $LOG_FILE
   - Redeploy the agent if needed:
     kubectl delete -f $PORTAINER_AGENT_URL
     kubectl apply -f $PORTAINER_AGENT_URL --validate=false

5. For Kubernetes API authentication (optional):
   - If Portainer requires direct API access, copy the kubeconfig:
     scp $KUBECONFIG user@192.168.4.109:/path/to/kubeconfig
   - Use the kubeconfig in Portainer’s Kubernetes environment settings (if supported) or for manual kubectl commands
   - Example: Replace 'user' and '/path/to/kubeconfig' with appropriate values

6. For Docker management in Portainer (optional):
   - To manage Docker on this server, expose the Docker daemon (e.g., on port 2375):
     sudo systemctl edit docker.service
     Add under [Service]:
       ExecStart=/usr/bin/dockerd -H fd:// -H tcp://0.0.0.0:2375
     Restart Docker:
       sudo systemctl restart docker
   - In Portainer, add a Docker environment using tcp://$KUBE_SERVER:2375

=============================================================
"
    echo "$instructions"
    log "$instructions"
}

# Ensure diagnostics run on exit
trap 'display_diagnostic_summary; display_portainer_instructions' EXIT

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

# Check for network conflicts
check_network_conflicts || log "Proceeding despite potential network conflict, may affect Minikube start"

# Backup current IPTABLES rules
IPTABLES_BACKUP="/tmp/iptables_backup_$(date +%Y%m%d_%H%M%S).rules"
log "Backing up current IPTABLES rules to $IPTABLES_BACKUP"
sudo iptables-save > "$IPTABLES_BACKUP"
check_status "Backing up IPTABLES rules"

# Add required rules if they don't exist
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
sudo install -o root -g root -m 0755 "$TEMP_DIR/k tonic" /usr/local/bin/kubectl
check_status "Installing kubectl"
rm "$TEMP_DIR/kubectl"

# Clean up existing Minikube
log "Cleaning up existing Minikube instance"
sg docker -c "minikube delete" || true

# Start Minikube with default subnet first
log "Starting Minikube with Docker driver (default subnet), $MINIKUBE_MEMORY MB, $MINIKUBE_CPUS CPUs, $MINIKUBE_DISK disk"
timeout 900 sg docker -c "minikube start --driver=docker --cpus=$MINIKUBE_CPUS --memory=$MINIKUBE_MEMORY --disk-size=$MINIKUBE_DISK --wait=false -v=9" 2>&1 | sudo tee -a "$LOG_FILE" || {
    log "ERROR: Minikube start with default subnet failed"
    log "Attempting with custom subnet $DOCKER_NETWORK"
    timeout 900 sg docker -c "minikube start --driver=docker --subnet=$DOCKER_NETWORK --cpus=$MINIKUBE_CPUS --memory=$MINIKUBE_MEMORY --disk-size=$MINIKUBE_DISK --wait=false -v=9" 2>&1 | sudo tee -a "$LOG_FILE" || {
        log "ERROR: Minikube start with custom subnet also failed"
        log "Attempting fallback with 'none' driver"
        timeout 900 sg docker -c "minikube start --driver=none --cpus=$MINIKUBE_CPUS --memory=$MINIKUBE_MEMORY --disk-size=$MINIKUBE_DISK --wait=false -v=9" 2>&1 | sudo tee -a "$LOG_FILE" || {
            log "ERROR: Minikube start with 'none' driver also failed"
            exit 1
        }
    }
}
check_status "Starting Minikube"

# Get Minikube VM IP
log "Detecting Minikube VM IP"
MINIKUBE_IP=$(minikube ip 2>&1) || {
    log "ERROR: Could not detect Minikube VM IP. Output: $MINIKUBE_IP"
    exit 1
}
log "Detected Minikube VM IP: $MINIKUBE_IP"

# Verify Minikube status
log "Verifying Minikube status"
minikube_status=$(minikube status 2>&1)
if ! echo "$minikube_status" | grep -q "host: Running"; then
    log "ERROR: Minikube is not running. Status: $minikube_status"
    exit 1
fi
log "Minikube is running"

# Configure kubeconfig for local operations
log "Setting kubeconfig for local operations"
kubectl config use-context minikube
kubectl config set-cluster minikube --server=https://$MINIKUBE_IP:$KUBERNETES_PORT
check_status "Configuring local kubeconfig"

# Deploy Portainer agent
log "Deploying Portainer agent"
set +e
curl -Lo "$TEMP_DIR/$PORTAINER_AGENT_YAML" "$PORTAINER_AGENT_URL"
kubectl apply -f "$TEMP_DIR/$PORTAINER_AGENT_YAML" --validate=false 2>&1 | sudo tee -a "$LOG_FILE"
if [ $? -ne 0 ]; then
    log "WARNING: Failed to deploy Portainer agent, continuing with diagnostics"
fi
rm "$TEMP_DIR/$PORTAINER_AGENT_YAML"
set -e

# Verify Portainer agent
log "Verifying Portainer agent deployment"
timeout 2m bash -c "
    until kubectl get pods -n portainer -l app=portainer-agent -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q Running; do
        sleep 5
        log \"Waiting for Portainer agent pod to be Running...\"
    done
" || {
    log "WARNING: Portainer agent pod failed to reach Running state within 2 minutes, continuing with diagnostics"
}
log "Portainer agent verification attempted"

# Configure IPTABLES NAT for Kubernetes API
log "Configuring IPTABLES NAT for Kubernetes API"
sudo iptables -t nat -A PREROUTING -p tcp -d "$SERVER_IP" --dport "$KUBERNETES_PORT" -j DNAT --to-destination "$MINIKUBE_IP:$KUBERNETES_PORT" 2>&1 | sudo tee -a "$LOG_FILE"
sudo iptables -t nat -A POSTROUTING -p tcp -d "$MINIKUBE_IP" --dport "$KUBERNETES_PORT" -j MASQUERADE 2>&1 | sudo tee -a "$LOG_FILE"
check_status "Configuring IPTABLES NAT rules"

# Save the updated IPTABLES NAT rules
log "Saving updated IPTABLES NAT rules"
sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
check_status "Saving IPTABLES NAT rules"

# Update kubeconfig for external access
log "Updating kubeconfig for external access"
kubectl config set-cluster minikube --server=https://$KUBE_SERVER:$KUBERNETES_PORT
check_status "Configuring external kubeconfig"

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
ExecStart=/usr/local/bin/minikube start --driver=docker --cpus=$MINIKUBE_CPUS --memory=$MINIKUBE_MEMORY --disk-size=$MINIKUBE_DISK --wait=false
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
echo "=============================================================" | tee -a /tmp/diagnostic_results.txt
echo "Diagnostic Test Results" | tee -a /tmp/diagnostic_results.txt
echo "Minikube VM IP: $MINIKUBE_IP" | tee -a /tmp/diagnostic_results.txt
echo "=============================================================" | tee -a /tmp/diagnostic_results.txt
run_test "Check Minikube version" "minikube version"
run_test "Check Minikube status" "minikube status"
run_test "Check kubectl client version" "kubectl version --client"
run_test "Check cluster info" "kubectl cluster-info"
run_test "Check nodes" "kubectl get nodes"
run_test "Check Portainer agent pods" "kubectl get pods -n portainer"
run_test "Check Portainer agent service" "kubectl get svc -n portainer"
run_test "Check systemd service enabled" "systemctl is-enabled minikube.service"
run_test "Check Docker container status" "docker ps -a --filter name=minikube"
run_test "Check Docker network configuration" "docker network ls --filter driver=bridge"
run_test "Check Kubernetes API connectivity" "curl -k https://$KUBE_SERVER:$KUBERNETES_PORT"
display_diagnostic_summary

# Display Portainer instructions
display_portainer_instructions

# Final status
log "Minikube installation completed successfully. Check status with 'minikube status'"
echo "============================================================="
echo "Minikube Installation Succeeded!"
echo "Check logs at: $LOG_FILE"
echo "IPTABLES backup saved at: $IPTABLES_BACKUP"
echo "To manage Minikube, use: minikube [start|stop|status]"
echo "============================================================="