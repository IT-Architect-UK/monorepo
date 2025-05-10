#!/bin/bash

# Define log file
LOGFILE="install_log.txt"

# Log the start of the installation (only to log file)
echo "Starting installation at $(date)" >> $LOGFILE

# Introduction (displayed on terminal and logged)
echo "This script will install Minikube, kubectl, and enable the Minikube dashboard on Ubuntu 24.04." | tee -a $LOGFILE
echo "It will allocate 8 CPUs and 16GB of memory to Minikube." | tee -a $LOGFILE
echo "Please ensure you have sudo privileges and internet access." | tee -a $LOGFILE
echo "The script will check each step before proceeding." | tee -a $LOGFILE

# Function to log commands to screen and file
log_command() {
    echo "Running: $@" | tee -a $LOGFILE
    "$@" 2>&1 | tee -a $LOGFILE
    return ${PIPESTATUS[0]}
}

# Function to check if a command was successful
check_success() {
    if [ $? -eq 0 ]; then
        echo "$1 succeeded." | tee -a $LOGFILE
    else
        echo "$1 failed. Check $LOGFILE for details." | tee -a $LOGFILE
        exit 1
    fi
}

# Check if user is in docker group; if not, add and exit
if ! groups | grep -q docker; then
    echo "Adding user to docker group..." | tee -a $LOGFILE
    sudo usermod -aG docker $USER
    check_success "Adding user to docker group"
    echo "Please log out and log back in for the group changes to take effect, then run this script again." | tee -a $LOGFILE
    exit 1
fi

# Update system
echo "Updating system..." | tee -a $LOGFILE
log_command sudo apt update
check_success "apt update"
log_command sudo apt upgrade -y
check_success "apt upgrade"

# Install dependencies
echo "Installing dependencies..." | tee -a $LOGFILE
log_command sudo apt install -y curl apt-transport-https ca-certificates software-properties-common
check_success "Installing dependencies"

# Set up Docker repository
echo "Setting up Docker repository..." | tee -a $LOGFILE
log_command sudo mkdir -p /etc/apt/keyrings
check_success "Creating keyrings directory"
log_command curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
check_success "Adding Docker GPG key"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
check_success "Adding Docker repository"
log_command sudo apt update
check_success "apt update after adding Docker repository"

# Install Docker
echo "Installing Docker..." | tee -a $LOGFILE
log_command sudo apt install -y docker-ce docker-ce-cli containerd.io
check_success "Installing Docker"
log_command docker --version
check_success "Checking Docker version"

# Install kubectl
echo "Installing kubectl..." | tee -a $LOGFILE
log_command curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
check_success "Downloading kubectl"
log_command chmod +x kubectl
check_success "Making kubectl executable"
log_command sudo mv kubectl /usr/local/bin/
check_success "Moving kubectl to /usr/local/bin"
log_command kubectl version --client
check_success "Checking kubectl version"

# Install Minikube
echo "Installing Minikube..." | tee -a $LOGFILE
log_command curl -Lo minikube https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
check_success "Downloading Minikube"
log_command chmod +x minikube
check_success "Making Minikube executable"
log_command sudo mv minikube /usr/local/bin/
check_success "Moving Minikube to /usr/local/bin"
log_command minikube version
check_success "Checking Minikube version"

# Start Minikube with Docker driver, 8 CPUs, and 16GB memory
echo "Starting Minikube..." | tee -a $LOGFILE
log_command minikube start --driver=docker --cpus=8 --memory=16384
check_success "Starting Minikube"

# Enable Minikube dashboard
echo "Enabling Minikube dashboard..." | tee -a $LOGFILE
log_command minikube addons enable dashboard
check_success "Enabling dashboard"

# Verify installation
echo "Verifying installation..." | tee -a $LOGFILE
log_command minikube status
check_success "Checking Minikube status"
log_command kubectl cluster-info
check_success "Checking cluster info"

# Completion message
echo "Installation complete. Check $LOGFILE for details." | tee -a $LOGFILE
echo "To access the dashboard, run: minikube dashboard --url" | tee -a $LOGFILE
echo "If there are any errors, refer to the log file and the Minikube documentation." | tee -a $LOGFILE