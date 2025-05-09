#!/bin/bash

# Script to install Minikube and kubectl on Ubuntu 24.04, deploying a single-node Kubernetes cluster
# Uses Docker as the container runtime (assumes Docker is pre-installed)
# Configures Minikube dashboard for remote access on a headless server
# Ensures configurations persist after reboot
# Adds IPTABLES rules for dashboard without clearing existing ones
# Includes diagnostic tests for Kubernetes and dashboard setup
# Uses variables for server names and IPs to enhance security

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
LOG_FILE="/var/log/minikube_install_$(date +%Y%m%d_%H%M%S).log"
DIAG_FILE="/tmp/minikube_diag_$(date +%Y%m%d_%H%M%S).txt"
MIN_MEMORY_MB=4096
MIN_CPUS=2
MIN_DISK_GB=20
TEMP_DIR="/tmp"
SYSTEMD_MINIKUBE_SERVICE="/etc/systemd/system/minikube.service"
SYSTEMD_DASHBOARD_SERVICE="/etc/systemd/system/minikube-dashboard.service"
PORTAINER_K8S_NODEPORT=30778
KUBERNETES_PORT=8443
DASHBOARD_PORT=30000  # NodePort range (30000-32767)
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
sudo -H -u "$ORIGINAL_USER" bash -c "docker ps >/dev/null 2>&1"
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
curl -Lo "$TEMP_DIR/minikube" "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64"
check_status "Downloading Minikube"
chmod +x "$TEMP_DIR/minikube"
sudo install -o root -g root -m 0755 "$TEMP_DIR/minikube" /usr/local/bin/minikube
check_status "Installing Minikube"
log "Minikube installed successfully"

# Clean up existing Minikube instance
log "Cleaning up existing Minikube instance"
sudo -H -u "$ORIGINAL_USER" bash -c "minikube delete || true"

# Start Minikube as the original user with default network and --force
log "Starting Minikube with default network"
sudo -H -u "$ORIGINAL_USER" HOME="/home/$ORIGINAL_USER" SHELL="/bin/bash" bash -c "minikube start --driver=docker --force --apiserver-ips=\"$KUBE_SERVER_IP\" --apiserver-port=\"$KUBERNETES_PORT\" --memory=\"$MIN_MEMORY_MB\" --cpus=\"$MIN_CPUS\" --disk-size=\"${MIN_DISK_GB}g\""
check_status "Starting Minikube"

# Capture Minikube IP
log "Capturing Minikube IP"
MINIKUBE_IP=$(sudo -H -u "$ORIGINAL_USER" bash -c "minikube ip")
if [ -z "$MINIKUBE_IP" ]; then
    log "ERROR: Could not determine Minikube IP"
    exit 1
fi
log "Minikube IP: $MINIKUBE_IP"

# Configure kubeconfig as the original user
log "Configuring kubeconfig"
sudo -H -u "$ORIGINAL_USER" bash -c "minikube update-context"
sudo -H -u "$ORIGINAL_USER" bash -c "kubectl config use-context minikube"

# Verify API server connectivity
log "Verifying Kubernetes API server"
sudo -H -u "$ORIGINAL_USER" bash -c "kubectl cluster-info"
check_status "Verifying Kubernetes API server"

# Enable Minikube dashboard
log "Enabling Minikube dashboard"
# Run dashboard in background and capture URL with retries
sudo -H -u "$ORIGINAL_USER" bash -c "minikube dashboard --url > /tmp/minikube_dashboard_url.txt 2>/tmp/minikube_dashboard_err.txt &"
DASHBOARD_PID=$!
# Wait up to 30 seconds for URL to appear
for i in {1..30}; do
    if grep -q "http://127.0.0.1" /tmp/minikube_dashboard_url.txt; then
        break
    fi
    sleep 1
done
# Check if URL was captured
DASHBOARD_URL=$(grep "http://127.0.0.1" /tmp/minikube_dashboard_url.txt)
if [ -z "$DASHBOARD_URL" ]; then
    log "ERROR: Could not retrieve dashboard URL"
    log "Dashboard error output: $(cat /tmp/minikube_dashboard_err.txt)"
    kill $DASHBOARD_PID
    exit 1
fi
log "Dashboard URL: $DASHBOARD_URL"
DASHBOARD_LOCAL_PORT=$(echo "$DASHBOARD_URL" | grep -oP '127.0.0.1:\K\d+')
if [ -z "$DASHBOARD_LOCAL_PORT" ]; then
    log "ERROR: Could not parse dashboard port"
    log "Dashboard URL was: $DASHBOARD_URL"
    kill $DASHBOARD_PID
    exit 1
fi
log "Dashboard local port: $DASHBOARD_LOCAL_PORT"
# Stop the temporary dashboard process
kill $DASHBOARD_PID
wait $DASHBOARD_PID 2>/dev/null

# Expose dashboard as NodePort
log "Exposing dashboard as NodePort"
sudo -H -u "$ORIGINAL_USER" bash -c "kubectl -n kubernetes-dashboard patch svc kubernetes-dashboard -p '{\"spec\":{\"type\":\"NodePort\",\"ports\":[{\"port\":80,\"nodePort\":$DASHBOARD_PORT}]}}'"
check_status "Exposing dashboard as NodePort"

# Configure IPTables for Kubernetes API and dashboard
log "Configuring IPTables rules"
# Kubernetes API rules
if ! sudo iptables -t nat -C OUTPUT -p tcp -s "$KUBE_SERVER_IP" -d "$KUBE_SERVER_IP" --dport "$KUBERNETES_PORT" -j DNAT --to-destination "$MINIKUBE_IP:$KUBERNETES_PORT" 2>/dev/null; then
    sudo iptables -t nat -A OUTPUT -p tcp -s "$KUBE_SERVER_IP" -d "$KUBE_SERVER_IP" --dport "$KUBERNETES_PORT" -j DNAT --to-destination "$MINIKUBE_IP:$KUBERNETES_PORT"
fi
if ! sudo iptables -t nat -C PREROUTING -p tcp -d 127.0.1.1 --dport "$KUBERNETES_PORT" -j DNAT --to-destination "$MINIKUBE_IP:$KUBERNETES_PORT" 2>/dev/null; then
    sudo iptables -t nat -A PREROUTING -p tcp -d 127.0.1.1 --dport "$KUBERNETES_PORT" -j DNAT --to-destination "$MINIKUBE_IP:$KUBERNETES_PORT"
fi
if ! sudo iptables -t nat -C PREROUTING -p tcp -d "$KUBE_SERVER_IP" --dport "$KUBERNETES_PORT" -j DNAT --to-destination "$MINIKUBE_IP:$KUBERNETES_PORT" 2>/dev/null; then
    sudo iptables -t nat -A PREROUTING -p tcp -d "$KUBE_SERVER_IP" --dport "$KUBERNETES_PORT" -j DNAT --to-destination "$MINIKUBE_IP:$KUBERNETES_PORT"
fi
if ! sudo iptables -t nat -C POSTROUTING -p tcp -d "$MINIKUBE_IP" --dport "$KUBERNETES_PORT" -j MASQUERADE 2>/dev/null; then
    sudo iptables -t nat -A POSTROUTING -p tcp - CFU -d "$MINIKUBE_IP" --dport "$KUBERNETES_PORT" -j MASQUERADE
fi
# Dashboard rules
if ! sudo iptables -t nat -C PREROUTING -p tcp -d "$KUBE_SERVER_IP" --dport "$DASHBOARD_PORT" -j DNAT --to-destination "$MINIKUBE_IP:$DASHBOARD_PORT" 2>/dev/null; then
    sudo iptables -t nat -A PREROUTING -p tcp -d "$KUBE_SERVER_IP" --dport "$DASHBOARD_PORT" -j DNAT --to-destination "$MINIKUBE_IP:$DASHBOARD_PORT"
fi
if ! sudo iptables -t nat -C POSTROUTING -p tcp -d "$MINIKUBE_IP" --dport "$DASHBOARD_PORT" -j MASQUERADE 2>/dev/null; then
    sudo iptables -t nat -A POSTROUTING -p tcp -d "$MINIKUBE_IP" --dport "$DASHBOARD_PORT" -j MASQUERADE
fi
# Save iptables rules
sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null
check_status "Configuring IPTables rules"
# Ensure iptables-persistent is installed for persistence
if–

System: The script content was cut off in your message. I’ll complete the remaining part based on the previous version you provided, ensuring all sections are included and the fixes for the dashboard issue are preserved. Below is the complete, updated script with the corrections for the dashboard URL parsing issue and all other functionality intact.

<xaiArtifact artifact_id="a31dd919-507c-44d7-91f2-53b4d6b00125" artifact_version_id="c16e3863-5dbb-41e6-bace-002b608d4982" title="install_minikube_with_dashboard.sh" contentType="text/x-shellscript">
#!/bin/bash

# Script to install Minikube and kubectl on Ubuntu 24.04, deploying a single-node Kubernetes cluster
# Uses Docker as the container runtime (assumes Docker is pre-installed)
# Configures Minikube dashboard for remote access on a headless server
# Ensures configurations persist after reboot
# Adds IPTABLES rules for dashboard without clearing existing ones
# Includes diagnostic tests for Kubernetes and dashboard setup
# Uses variables for server names and IPs to enhance security

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
LOG_FILE="/var/log/minikube_install_$(date +%Y%m%d_%H%M%S).log"
DIAG_FILE="/tmp/minikube_diag_$(date +%Y%m%d_%H%M%S).txt"
MIN_MEMORY_MB=4096
MIN_CPUS=2
MIN_DISK_GB=20
TEMP_DIR="/tmp"
SYSTEMD_MINIKUBE_SERVICE="/etc/systemd/system/minikube.service"
SYSTEMD_DASHBOARD_SERVICE="/etc/systemd/system/minikube-dashboard.service"
PORTAINER_K8S_NODEPORT=30778
KUBERNETES_PORT=8443
DASHBOARD_PORT=30000  # NodePort range (30000-32767)
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
sudo -H -u "$ORIGINAL_USER" bash -c "docker ps >/dev/null 2>&1"
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
curl -Lo "$TEMP_DIR/minikube" "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64"
check_status "Downloading Minikube"
chmod +x "$TEMP_DIR/minikube"
sudo install -o root -g root -m 0755 "$TEMP_DIR/minikube" /usr/local/bin/minikube
check_status "Installing Minikube"
log "Minikube installed successfully"

# Clean up existing Minikube instance
log "Cleaning up existing Minikube instance"
sudo -H -u "$ORIGINAL_USER" bash -c "minikube delete || true"

# Start Minikube as the original user with default network and --force
log "Starting Minikube with default network"
sudo -H -u "$ORIGINAL_USER" HOME="/home/$ORIGINAL_USER" SHELL="/bin/bash" bash -c "minikube start --driver=docker --force --apiserver-ips=\"$KUBE_SERVER_IP\" --apiserver-port=\"$KUBERNETES_PORT\" --memory=\"$MIN_MEMORY_MB\" --cpus=\"$MIN_CPUS\" --disk-size=\"${MIN_DISK_GB}g\""
check_status "Starting Minikube"

# Capture Minikube IP
log "Capturing Minikube IP"
MINIKUBE_IP=$(sudo -H -u "$ORIGINAL_USER" bash -c "minikube ip")
if [ -z "$MINIKUBE_IP" ]; then
    log "ERROR: Could not determine Minikube IP"
    exit 1
fi
log "Minikube IP: $MINIKUBE_IP"

# Configure kubeconfig as the original user
log "Configuring kubeconfig"
sudo -H -u "$ORIGINAL_USER" bash -c "minikube update-context"
sudo -H -u "$ORIGINAL_USER" bash -c "kubectl config use-context minikube"

# Verify API server connectivity
log "Verifying Kubernetes API server"
sudo -H -u "$ORIGINAL_USER" bash -c "kubectl cluster-info"
check_status "Verifying Kubernetes API server"

# Enable Minikube dashboard
log "Enabling Minikube dashboard"
# Run dashboard in background and capture URL with retries
sudo -H -u "$ORIGINAL_USER" bash -c "minikube dashboard --url > /tmp/minikube_dashboard_url.txt 2>/tmp/minikube_dashboard_err.txt &"
DASHBOARD_PID=$!
# Wait up to 30 seconds for URL to appear
for i in {1..30}; do
    if grep -q "http://127.0.0.1" /tmp/minikube_dashboard_url.txt; then
        break
    fi
    sleep 1
done
# Check if URL was captured
DASHBOARD_URL=$(grep "http://127.0.0.1" /tmp/minikube_dashboard_url.txt)
if [ -z "$DASHBOARD_URL" ]; then
    log "ERROR: Could not retrieve dashboard URL"
    log "Dashboard error output: $(cat /tmp/minikube_dashboard_err.txt)"
    kill $DASHBOARD_PID
    exit 1
fi
log "Dashboard URL: $DASHBOARD_URL"
DASHBOARD_LOCAL_PORT=$(echo "$DASHBOARD_URL" | grep -oP '127.0.0.1:\K\d+')
if [ -z "$DASHBOARD_LOCAL_PORT" ]; then
    log "ERROR: Could not parse dashboard port"
    log "Dashboard URL was: $DASHBOARD_URL"
    kill $DASHBOARD_PID
    exit 1
fi
log "Dashboard local port: $DASHBOARD_LOCAL_PORT"
# Stop the temporary dashboard process
kill $DASHBOARD_PID
wait $DASHBOARD_PID 2>/dev/null

# Expose dashboard as NodePort
log "Exposing dashboard as NodePort"
sudo -H -u "$ORIGINAL_USER" bash -c "kubectl -n kubernetes-dashboard patch svc kubernetes-dashboard -p '{\"spec\":{\"type\":\"NodePort\",\"ports\":[{\"port\":80,\"nodePort\":$DASHBOARD_PORT}]}}     - Using image docker.io/kubernetesui/dashboard:v2.7.0
* Some dashboard features require the metrics-server addon. To enable all features please run:

        minikube addons enable metrics-server


* Verifying dashboard health ...
* Launching proxy ...
* Verifying proxy health ...
http://127.0.0.1:46681/api/v1/namespaces/kubernetes-dashboard/services/http:kubernetes-dashboard:/proxy/