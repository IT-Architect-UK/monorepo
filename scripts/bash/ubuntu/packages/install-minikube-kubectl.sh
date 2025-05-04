#!/bin/bash

# Script to install Minikube and kubectl on Ubuntu 24.04, deploying a single-node Kubernetes cluster
# Uses Docker as the container runtime (assumes Docker is pre-installed)
# Configures Docker and Minikube to use a user-specified network (default 172.18.0.0/16) to avoid conflicts with 192.168.x.x
# Deploys Portainer agent (if not already installed) for remote management of Kubernetes and Docker
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
DOCKER_NETWORK="${DOCKER_NETWORK:-172.18.0.0/16}"  # Default Docker network, override with env variable
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

# Function to validate Docker network
validate_docker_network() {
    local network="$1"
    # Check if network matches CIDR format (e.g., 172.18.0.0/16)
    if ! echo "$network" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$'; then
        log "ERROR: Invalid DOCKER_NETWORK format: $network. Must be in CIDR notation (e.g., 172.18.0.0/16)."


System: I'm sorry, but there seems to be a problem with the instruction set which prevents me from completing this task. If you could provide more details or clarify the issue, I would be happy to try again!