#!/bin/bash

# Script to install Minikube and kubectl on Ubuntu 24.04, deploying a single-node Kubernetes cluster
# Uses Docker as the container runtime (assumes Docker is pre-installed)
# Configures Minikube dashboard for remote access on a headless server
# Enables Metrics Server for resource usage data
# Configures dashboard admin access via cluster role binding
# Ensures configurations persist after reboot
# Adds IPTABLES rules for dashboard and Kubernetes API with input acceptance
# Includes diagnostic tests for Kubernetes, dashboard, container status, iptables, pod logs, kubeconfig, and network
# Optimized for 32GB memory and 16 vCPUs

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
MIN_MEMORY_MB=16384  # 16GB for stability with 32GB system
MIN_CPUS=8          # 8 CPUs for stability with 16 vCPUs
MIN_DISK_GB=20
TEMP_DIR="/tmp"
SYSTEMD_MINIKUBE_SERVICE="/etc/systemd/system/minikube.service"
SYSTEMD_DASHBOARD_SERVICE="/etc/systemd/system/minikube-dashboard.service"
PORTAINER_K8S_NODEPORT=30778
KUBERNETES_PORT=8443
DASHBOARD_PORT=30000  # NodePort range (30000-32767)
KUBECONFIG="/home/$ORIGINAL_USER/.kube/config"
KUBECONFIG_BACKUP="/home/$ORIGINAL_USER/.kube/config.bak"
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

# Check Docker service without restarting if running
log "Checking Docker service"
if sudo systemctl is-active docker >/dev/null 2>&1; then
    log "Docker service is already running, skipping restart"
else
    log "Restarting Docker service"
    sudo systemctl restart docker
    sleep 15
    sudo systemctl status docker >/dev/null 2>&1
    check_status "Docker service verification"
fi

# Force iptables-legacy for compatibility
log "Setting iptables to legacy mode"
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy >/dev/null 2>&1
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy >/dev/null 2>&1

# Check system resources
log "Checking system resources"
free -m >> "$LOG_FILE"
nproc >> "$LOG_FILE"
docker info --format '{{.MemTotal}} {{.NCPU}}' >> "$LOG_FILE"

# Check Docker bridge network
log "Checking Docker bridge network"
BRIDGE="minikube"
for i in {1..3}; do
    if ! sudo -H -u "$ORIGINAL_USER" bash -c "docker network ls --filter 'name=$BRIDGE' --format '{{.Name}}' | grep -q $BRIDGE"; then
        log "Creating Minikube bridge network (attempt $i)"
        sudo -H -u "$ORIGINAL_USER" bash -c "docker network create $BRIDGE" >> "$LOG_FILE" 2>&1
        check_status "Creating Minikube bridge network"
    fi
    # Get bridge interface name (e.g., br-<network-id>)
    NETWORK_ID=$(sudo -H -u "$ORIGINAL_USER" bash -c "docker network ls --filter 'name=$BRIDGE' --format '{{.ID}}'")
    if [ -n "$NETWORK_ID" ]; then
        BRIDGE_IFACE=$(ip link show | grep -o "br-$NETWORK_ID[^:]*" | head -n 1)
        if [ -n "$BRIDGE_IFACE" ] && ip link show "$BRIDGE_IFACE" >/dev/null 2>&1; then
            log "Using Docker bridge interface: $BRIDGE_IFACE"
            break
        fi
    fi
    log "Docker bridge $BRIDGE not found at IP level, retrying (attempt $i)"
    sleep 5
done
if [ -z "$BRIDGE_IFACE" ] || ! ip link show "$BRIDGE_IFACE" >/dev/null 2>&1; then
    log "ERROR: Docker bridge $BRIDGE not found at IP level after retries"
    log "Docker network inspect output:"
    sudo -H -u "$ORIGINAL_USER" bash -c "docker network inspect $BRIDGE" >> "$LOG_FILE" 2>&1
    exit 1
fi
log "Docker network inspect output:"
sudo -H -u "$ORIGINAL_USER" bash -c "docker network inspect $BRIDGE" >> "$LOG_FILE" 2>&1

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
sudo -H -u "$ORIGINAL_USER" HOME="/home/$ORIGINAL_USER" SHELL="/bin/bash" bash -c "minikube start --driver=docker --force --apiserver-ips=\"$KUBE_SERVER_IP\" --apiserver-port=\"$KUBERNETES_PORT\" --memory=\"$MIN_MEMORY_MB\" --cpus=\"$MIN_CPUS\" --disk-size=\"${MIN_DISK_GB}g\" --network=$BRIDGE >$TEMP_DIR/minikube_start.log 2>&1"
check_status "Starting Minikube"
cat "$TEMP_DIR/minikube_start.log" >> "$LOG_FILE"

# Verify Minikube container is running
log "Verifying Minikube container"
for i in {1..15}; do
    if sudo -H -u "$ORIGINAL_USER" bash -c "docker ps --filter 'name=minikube' --format '{{.Names}}' | grep -q minikube"; then
        log "Minikube container is running"
        break
    fi
    log "Minikube container not running, retrying (attempt $i)"
    sudo systemctl restart minikube.service
    sleep 10
done
if ! sudo -H -u "$ORIGINAL_USER" bash -c "docker ps --filter 'name=minikube' --format '{{.Names}}' | grep -q minikube"; then
    log "ERROR: Minikube container failed to start"
    log "Docker container logs:"
    sudo -H -u "$ORIGINAL_USER" bash -c "docker logs minikube" >> "$LOG_FILE" 2>&1
    exit 1
fi
# Monitor container health for 180 seconds
log "Monitoring Minikube container health for 180 seconds"
for i in {1..36}; do
    if sudo -H -u "$ORIGINAL_USER" bash -c "docker ps --filter 'name=minikube' --filter 'status=running' --format '{{.Names}}' | grep -q minikube"; then
        log "Minikube container still running (check $i)"
        free -m >> "$LOG_FILE"
        docker info --format '{{.MemTotal}} {{.NCPU}}' >> "$LOG_FILE"
    else
        log "ERROR: Minikube container stopped during health check"
        log "Docker container logs:"
        sudo -H -u "$ORIGINAL_USER" bash -c "docker logs minikube" >> "$LOG_FILE" 2>&1
        exit 1
    fi
    sleep 5
done

# Re-verify Docker bridge after Minikube startup
log "Re-verifying Docker bridge after Minikube startup"
NETWORK_ID=$(sudo -H -u "$ORIGINAL_USER" bash -c "docker network ls --filter 'name=$BRIDGE' --format '{{.ID}}'")
if [ -n "$NETWORK_ID" ]; then
    BRIDGE_IFACE=$(ip link show | grep -o "br-$NETWORK_ID[^:]*" | head -n 1)
    if [ -n "$BRIDGE_IFACE" ] && ip link show "$BRIDGE_IFACE" >/dev/null 2>&1; then
        log "Confirmed Docker bridge interface: $BRIDGE_IFACE"
    else
        log "ERROR: Docker bridge $BRIDGE not found at IP level after Minikube startup"
        log "Docker network inspect output:"
        sudo -H -u "$ORIGINAL_USER" bash -c "docker network inspect $BRIDGE" >> "$LOG_FILE" 2>&1
        exit 1
    fi
else
    log "ERROR: Minikube network not found after startup"
    exit 1
fi

# Log Docker system info
log "Docker system info"
sudo -H -u "$ORIGINAL_USER" bash -c "docker info" >> "$LOG_FILE"

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
# Backup existing kubeconfig
if [ -f "$KUBECONFIG" ]; then
    sudo cp "$KUBECONFIG" "$KUBECONFIG_BACKUP"
    log "Backed up kubeconfig to $KUBECONFIG_BACKUP"
fi
for i in {1..3}; do
    sudo -H -u "$ORIGINAL_USER" bash -c "minikube update-context 2>>$LOG_FILE"
    sudo -H -u "$ORIGINAL_USER" bash -c "kubectl config use-context minikube 2>>$LOG_FILE"
    sudo -H -u "$ORIGINAL_USER" bash -c "kubectl config set-cluster minikube --server=https://$MINIKUBE_IP:$KUBERNETES_PORT 2>>$LOG_FILE"
    if sudo -H -u "$ORIGINAL_USER" bash -c "kubectl config view --minify | grep -q 'server: https://$MINIKUBE_IP:$KUBERNETES_PORT'"; then
        log "kubeconfig configured successfully"
        break
    fi
    log "ERROR: kubeconfig not correctly configured, retrying (attempt $i)"
    sleep 2
done
if ! sudo -H -u "$ORIGINAL_USER" bash -c "kubectl config view --minify | grep -q 'server: https://$MINIKUBE_IP:$KUBERNETES_PORT'"; then
    log "ERROR: kubeconfig still invalid, restoring backup"
    sudo cp "$KUBECONFIG_BACKUP" "$KUBECONFIG" 2>>"$LOG_FILE"
    check_status "Restoring kubeconfig"
fi

# Verify API server connectivity
log "Verifying Kubernetes API server"
sudo -H -u "$ORIGINAL_USER" bash -c "kubectl cluster-info 2>>$LOG_FILE"
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
    kill -9 $DASHBOARD_PID 2>/dev/null
    exit 1
fi
log "Dashboard URL: $DASHBOARD_URL"
DASHBOARD_LOCAL_PORT=$(echo "$DASHBOARD_URL" | grep -oP '127.0.0.1:\K\d+')
if [ -z "$DASHBOARD_LOCAL_PORT" ]; then
    log "ERROR: Could not parse dashboard port"
    log "Dashboard URL was: $DASHBOARD_URL"
    kill -9 $DASHBOARD_PID 2>/dev/null
    exit 1
fi
log "Dashboard local port: $DASHBOARD_LOCAL_PORT"
# Stop the temporary dashboard process
kill -9 $DASHBOARD_PID 2>/dev/null
wait $DASHBOARD_PID 2>/dev/null

# Expose dashboard as NodePort with retry
log "Exposing dashboard as NodePort"
for i in {1..5}; do
    sudo -H -u "$ORIGINAL_USER" bash -c "kubectl -n kubernetes-dashboard patch svc kubernetes-dashboard -p '{\"spec\":{\"type\":\"NodePort\",\"ports\":[{\"port\":80,\"nodePort\":$DASHBOARD_PORT}]}}' 2>>$LOG_FILE"
    if [ $? -eq 0 ]; then
        # Verify NodePort
        NODEPORT=$(sudo -H -u "$ORIGINAL_USER" bash -c "kubectl -n kubernetes-dashboard get svc kubernetes-dashboard -o jsonpath='{.spec.ports[0].nodePort}'")
        if [ "$NODEPORT" = "$DASHBOARD_PORT" ]; then
            # Restart dashboard pod to ensure port binding
            sudo -H -u "$ORIGINAL_USER" bash -c "kubectl -n kubernetes-dashboard delete pod -l k8s-app=kubernetes-dashboard --wait=false 2>>$LOG_FILE"
            sleep 5
            break
        fi
        log "NodePort not set correctly, retrying (attempt $i)"
    fi
    sleep 2
done
check_status "Exposing dashboard as NodePort"
# Log dashboard service details
log "Dashboard service details"
sudo -H -u "$ORIGINAL_USER" bash -c "kubectl -n kubernetes-dashboard get svc kubernetes-dashboard -o yaml" >> "$LOG_FILE"

# Fallback: Expose dashboard via minikube service
log "Exposing dashboard via minikube service as fallback"
sudo -H -u "$ORIGINAL_USER" bash -c "minikube service kubernetes-dashboard -n kubernetes-dashboard --url > /tmp/minikube_service_url.txt 2>>$LOG_FILE &"
sleep 5
SERVICE_URL=$(cat /tmp/minikube_service_url.txt)
if [ -n "$SERVICE_URL" ]; then
    log "Dashboard service URL: $SERVICE_URL"
else
    log "WARNING: Could not retrieve dashboard service URL"
fi

# Enable Metrics Server
log "Enabling Metrics Server"
sudo -H -u "$ORIGINAL_USER" bash -c "minikube addons enable metrics-server 2>>$LOG_FILE"
check_status "Enabling Metrics Server"

# Configure dashboard admin access
log "Configuring dashboard admin access"
sudo -H -u "$ORIGINAL_USER" bash -c "kubectl create clusterrolebinding dashboard-admin --clusterrole=cluster-admin --serviceaccount=kubernetes-dashboard:kubernetes-dashboard 2>>$LOG_FILE"
check_status "Configuring dashboard admin access"

# Configure IPTables for Kubernetes API and dashboard
log "Configuring IPTables rules"
# Clean up conflicting MASQUERADE and DOCKER rules
sudo iptables -t nat -F POSTROUTING
sudo iptables -t nat -F DOCKER
# Filter table: Allow input for dashboard port on host and Minikube IP
if ! sudo iptables -C INPUT -p tcp -d "$KUBE_SERVER_IP" --dport "$DASHBOARD_PORT" -j ACCEPT 2>/dev/null; then
    sudo iptables -A INPUT -p tcp -d "$KUBE_SERVER_IP" --dport "$DASHBOARD_PORT" -j ACCEPT
fi
if ! sudo iptables -C INPUT -p tcp -d "$MINIKUBE_IP" --dport "$DASHBOARD_PORT" -j ACCEPT 2>/dev/null; then
    sudo iptables -A INPUT -p tcp -d "$MINIKUBE_IP" --dport "$DASHBOARD_PORT" -j ACCEPT
fi
# NAT table: Kubernetes API rules
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
    sudo iptables -t nat -A POSTROUTING -p tcp -d "$MINIKUBE_IP" --dport "$KUBERNETES_PORT" -j MASQUERADE
fi
# NAT table: Dashboard rules
if ! sudo iptables -t nat -C PREROUTING -p tcp -d "$KUBE_SERVER_IP" --dport "$DASHBOARD_PORT" -j DNAT --to-destination "$MINIKUBE_IP:$DASHBOARD_PORT" 2>/dev/null; then
    sudo iptables -t nat -A PREROUTING -p tcp -d "$KUBE_SERVER_IP" --dport "$DASHBOARD_PORT" -j DNAT --to-destination "$MINIKUBE_IP:$DASHBOARD_PORT"
fi
if ! sudo iptables -t nat -C POSTROUTING -p tcp -d "$MINIKUBE_IP" --dport "$DASHBOARD_PORT" -j MASQUERADE 2>/dev/null; then
    sudo iptables -t nat -A POSTROUTING -p tcp -d "$MINIKUBE_IP" --dport "$DASHBOARD_PORT" -j MASQUERADE
fi
# Update MASQUERADE and DOCKER rules with correct bridge
sudo iptables -t nat -A POSTROUTING -s 192.168.49.0/24 ! -o "$BRIDGE_IFACE" -j MASQUERADE
sudo iptables -t nat -A DOCKER -i "$BRIDGE_IFACE" -j RETURN
sudo iptables -t nat -A DOCKER -p tcp -d "$MINIKUBE_IP" --dport "$DASHBOARD_PORT" -j ACCEPT
# Save iptables rules
sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null
check_status "Configuring IPTables rules"
# Ensure iptables-persistent is installed for persistence
if ! dpkg -l | grep -q iptables-persistent; then
    log "Installing iptables-persistent"
    sudo apt update
    sudo apt install -y iptables-persistent
    check_status "Installing iptables-persistent"
fi
# Verify iptables rules
log "Verifying iptables rules"
sudo iptables -L INPUT -v -n >> "$LOG_FILE"
sudo iptables -t nat -L PREROUTING -v -n >> "$LOG_FILE"
sudo iptables -t nat -L POSTROUTING -v -n >> "$LOG_FILE"

# Configure systemd service for Minikube
log "Configuring systemd service for Minikube"
if [ -f "$SYSTEMD_MINIKUBE_SERVICE" ]; then
    log "Minikube systemd service already configured"
else
    sudo bash -c "cat << EOF > $SYSTEMD_MINIKUBE_SERVICE
[Unit]
Description=Minikube Kubernetes Cluster
After=network.target docker.service
Requires=docker.service

[Service]
User=$ORIGINAL_USER
Group=docker
ExecStart=/usr/local/bin/minikube start --driver=docker --force --apiserver-ips=$KUBE_SERVER_IP --apiserver-port=$KUBERNETES_PORT --memory=$MIN_MEMORY_MB --cpus=$MIN_CPUS --disk-size=${MIN_DISK_GB}g --network=$BRIDGE
ExecStop=/usr/local/bin/minikube stop
Restart=on-failure
RestartSec=10
Environment=\"HOME=/home/$ORIGINAL_USER\"

[Install]
WantedBy=multi-user.target
EOF"
    sudo systemctl daemon-reload
    sudo systemctl enable minikube.service
    sudo systemctl start minikube.service
    check_status "Configuring and starting Minikube systemd service"
fi

# Configure systemd service for Minikube dashboard
log "Configuring systemd service for Minikube dashboard"
if [ -f "$SYSTEMD_DASHBOARD_SERVICE" ]; then
    log "Dashboard systemd service already configured"
else
    sudo bash -c "cat << EOF > $SYSTEMD_DASHBOARD_SERVICE
[Unit]
Description=Minikube Dashboard Proxy
After=network.target minikube.service
Requires=minikube.service

[Service]
User=$ORIGINAL_USER
Group=docker
ExecStart=/usr/local/bin/minikube dashboard
ExecStop=/bin/kill -TERM \$MAINPID
Restart=on-failure
RestartSec=10
Environment=\"HOME=/home/$ORIGINAL_USER\"

[Install]
WantedBy=multi-user.target
EOF"
    sudo systemctl daemon-reload
    sudo systemctl enable minikube-dashboard.service
    sudo systemctl start minikube-dashboard.service
    check_status "Configuring and starting Dashboard systemd service"
fi

# Run diagnostic tests
log "Running diagnostic tests"
echo "=============================================================" >> "$DIAG_FILE"
echo "Diagnostic Test Results" >> "$DIAG_FILE"
echo "=============================================================" >> "$DIAG_FILE"
run_test "Check Minikube status" "minikube status"
run_test "Check Minikube service status" "systemctl status minikube.service"
run_test "Check kubectl client version" "kubectl version --client"
run_test "Check Kubernetes nodes" "kubectl get nodes"
run_test "Check Minikube container status" "docker ps --filter 'name=minikube' --format '{{.Names}} {{.Status}}'"
run_test "Check Docker events" "docker events --filter 'container=minikube' --since '10m' --until '0s'"
run_test "Check Docker bridge connectivity" "ip addr show $BRIDGE_IFACE && ping -c 1 $MINIKUBE_IP"
run_test "Check Dashboard pods" "kubectl get pods -n kubernetes-dashboard"
run_test "Check Dashboard pod logs" "kubectl -n kubernetes-dashboard logs -l k8s-app=kubernetes-dashboard --tail=10"
run_test "Check Dashboard service" "kubectl get svc -n kubernetes-dashboard"
run_test "Check Dashboard cluster IP" "kubectl -n kubernetes-dashboard get svc kubernetes-dashboard -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}' && curl -k -m 10 http://\$(kubectl -n kubernetes-dashboard get svc kubernetes-dashboard -o jsonpath='{.spec.clusterIP}'):80"
run_test "Check Minikube network configuration" "minikube ip && ip addr show $BRIDGE_IFACE"
run_test "Check kubeconfig" "kubectl config view --minify"
run_test "Check iptables hits" "sudo iptables -L INPUT -v -n && sudo iptables -t nat -L PREROUTING -v -n"
run_test "Check system resources" "free -m && nproc"
run_test "Check Minikube logs" "minikube logs -n 10"
run_test "Check Minikube container uptime" "docker inspect minikube --format '{{.State.Running}} {{.State.StartedAt}} {{.State.FinishedAt}}'"
run_test "Check system logs for shutdown" "journalctl -u docker --since '10 minutes ago' | grep -i 'stop\\|shutdown\\|kill'"
run_test "Check Minikube container ports" "docker port minikube && docker exec minikube ss -tuln | grep 30000"
run_test "Check CNI configuration" "docker exec minikube cat /etc/cni/net.d/00-minikube.conf"
run_test "Check Minikube systemd logs" "docker exec minikube journalctl --since '10 minutes ago' | grep -i 'shutdown\\|halt\\|poweroff'"
run_test "Check host processes" "ps aux | grep -i 'docker\\|minikube' | grep -v grep"
run_test "Check Dashboard connectivity (Minikube IP)" "curl -k -m 10 http://$MINIKUBE_IP:$DASHBOARD_PORT"
run_test "Check Kubernetes API connectivity (local Minikube IP)" "curl -k -m 10 https://$MINIKUBE_IP:$KUBERNETES_PORT"
run_test "Check Kubernetes API connectivity (local FQDN)" "curl -k -m 10 https://$KUBE_SERVER:$KUBERNETES_PORT"
run_test "Check Kubernetes API connectivity (local server IP)" "curl -k -m 10 https://$KUBE_SERVER_IP:$KUBERNETES_PORT"
run_test "Check Dashboard connectivity (NodePort)" "curl -k -m 10 http://$KUBE_SERVER_IP:$DASHBOARD_PORT"

# Display diagnostic summary
log "Displaying diagnostic summary"
echo "============================================================="
echo "Diagnostic Test Summary"
echo "============================================================="
cat "$DIAG_FILE"
echo "============================================================="
rm -f "$DIAG_FILE"

log "Minikube, kubectl, and dashboard installation completed successfully"
echo "Access the dashboard at: http://$KUBE_SERVER_IP:$DASHBOARD_PORT"
if [ -n "$SERVICE_URL" ]; then
    echo "Fallback dashboard URL: $SERVICE_URL"
fi