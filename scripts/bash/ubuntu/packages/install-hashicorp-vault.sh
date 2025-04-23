#!/bin/bash

# This script installs HashiCorp Vault on an Ubuntu system using HTTP on port 80.
# It checks for prerequisites, handles configuration dynamically, prompts the user for changes,
# and ensures the service starts correctly by identifying and fixing issues.

# Check if running in bash
if [ -z "$BASH_VERSION" ]; then
    echo "Error: This script must be run with bash, not sh or another shell."
    echo "Run it as: bash install-hashicorp-vault.sh or ./install-hashicorp-vault.sh"
    exit 1
fi

# Variables
INSTALL_DIR="/usr/local/bin"
LOG_FILE="/var/log/vault_install.log"
TEMP_DIR="/tmp/vault_install"
VAULT_CONFIG_DIR="/etc/vault.d"
VAULT_DATA_DIR="/opt/vault/data"
VAULT_CONFIG_FILE="$VAULT_CONFIG_DIR/vault.hcl"
VAULT_USER="vault"
VAULT_PORT=80
PROTOCOL="http"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")" || {
    echo "Error: Failed to create log directory $(dirname "$LOG_FILE")"
    exit 1
}

# Logging function
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
    log "ERROR: $1"
    echo "Error: $1" >&2
    exit 1
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error_exit "This script must be run as root (use sudo)"
fi

log "Starting Vault installation script"

# Check for required dependencies
log "Checking for required dependencies"
for cmd in curl unzip jq iptables ss; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log "Installing $cmd"
        apt-get update && apt-get install -y "$cmd" || error_exit "Failed to install $cmd"
    fi
done

# Prerequisite Checks
log "Performing prerequisite checks"

# Check if port 80 is in use
if ss -tuln | grep -q ":$VAULT_PORT "; then
    error_exit "Port $VAULT_PORT is already in use. Please free the port or choose a different one."
fi

# Check available disk space in /opt for Vault data directory
AVAILABLE_SPACE=$(df -k /opt | tail -1 | awk '{print $4}')
if [ "$AVAILABLE_SPACE" -lt 102400 ]; then  # Less than 100 MB
    log "WARNING: Low disk space in /opt: $AVAILABLE_SPACE KB available."
    echo "Vault requires sufficient disk space for its data directory."
    echo "Ensure at least 100 MB is available in /opt."
fi

# Inform user about locked memory requirements
echo "Vault requires the ability to lock memory to prevent sensitive data from being swapped to disk."
echo "Ensure that the 'vault' user has sufficient locked memory limit."
echo "After installation, you can check it with: sudo su - vault -c 'ulimit -l'"
echo "If it's too low, edit /etc/security/limits.conf and add:"
echo "vault soft memlock unlimited"
echo "vault hard memlock unlimited"
echo "Then, reboot or run 'sudo sysctl -p' to apply changes."
echo "Alternatively, you can disable mlock by adding 'disable_mlock = true' to $VAULT_CONFIG_FILE, but this reduces security."

# Fetch the latest Vault version
log "Fetching the latest Vault version"
VAULT_VERSION=$(curl -s https://releases.hashicorp.com/vault/index.json | jq -r '.versions | keys[]' | sort -V | tail -n 1)
if [ -z "$VAULT_VERSION" ]; then
    error_exit "Failed to fetch the latest Vault version"
fi
log "Latest Vault version: $VAULT_VERSION"

# Set VAULT_ZIP and VAULT_URL based on the latest version
VAULT_ZIP="vault_${VAULT_VERSION}_linux_amd64.zip"
VAULT_URL="https://releases.hashicorp.com/vault/${VAULT_VERSION}/${VAULT_ZIP}"

# Install iptables-persistent to save rules
if ! dpkg -l | grep -q iptables-persistent; then
    log "Installing iptables-persistent"
    apt-get install -y iptables-persistent || error_exit "Failed to install iptables-persistent"
fi

# Check for existing Vault installation
check_existing_vault() {
    if command -v vault >/dev/null 2>&1; then
        CURRENT_VERSION=$(vault --version | awk '{print $2}' | sed 's/v//')
        log "Found existing Vault version: $CURRENT_VERSION"
        return 0
    else
        log "No existing Vault installation found"
        return 1
    fi
}

# Prompt for action if Vault exists
handle_existing_vault() {
    log "Vault version $CURRENT_VERSION is already installed"
    echo "Existing Vault version $CURRENT_VERSION found"
    echo "1) Remove and install the latest version ($VAULT_VERSION)"
    echo "2) Upgrade to the latest version ($VAULT_VERSION)"
    echo "3) Exit"
    read -p "Select an option [1-3]: " choice
    case $choice in
        1)
            log "Removing existing Vault installation"
            rm -f "$INSTALL_DIR/vault" || error_exit "Failed to remove existing Vault"
            log "Existing Vault removed"
            return 0
            ;;
        2)
            log "Proceeding with upgrade to version $VAULT_VERSION"
            return 0
            ;;
        3)
            log "User chose to exit"
            exit 0
            ;;
        *)
            error_exit "Invalid option selected"
            ;;
    esac
}

# Download and install Vault
install_vault() {
    log "Creating temporary directory: $TEMP_DIR"
    mkdir -p "$TEMP_DIR" || error_exit "Failed to create temporary directory"

    log "Downloading Vault version $VAULT_VERSION"
    curl -s -o "$TEMP_DIR/$VAULT_ZIP" "$VAULT_URL" || error_exit "Failed to download Vault"

    log "Unzipping Vault"
    unzip -o "$TEMP_DIR/$VAULT_ZIP" -d "$TEMP_DIR" || error_exit "Failed to unzip Vault"

    log "Installing Vault to $INSTALL_DIR"
    mv "$TEMP_DIR/vault" "$INSTALL_DIR/" || error_exit "Failed to move Vault binary"
    chmod +x "$INSTALL_DIR/vault" || error_exit "Failed to set Vault permissions"

    log "Cleaning up temporary files"
    rm -rf "$TEMP_DIR" || log "Warning: Failed to clean up temporary directory"
}

# Configure Vault user and directories
configure_vault_user() {
    log "Configuring Vault user and directories"
    if ! id "$VAULT_USER" >/dev/null 2>&1; then
        useradd -r -s /bin/false "$VAULT_USER" || error_exit "Failed to create Vault user"
    fi
    mkdir -p "$VAULT_CONFIG_DIR" "$VAULT_DATA_DIR" || error_exit "Failed to create Vault directories"
    chown -R "$VAULT_USER:$VAULT_USER" "$VAULT_CONFIG_DIR" "$VAULT_DATA_DIR" || error_exit "Failed to set Vault directory permissions"
}

# Create Vault configuration for HTTP on port 80
create_vault_config() {
    log "Creating Vault configuration file"
    cat > "$VAULT_CONFIG_FILE" << EOF
storage "raft" {
  path = "$VAULT_DATA_DIR"
  node_id = "raft_node_1"
}

listener "tcp" {
  address = "0.0.0.0:$VAULT_PORT"
  tls_disable = true
}

api_addr = "$PROTOCOL://$FQDN:$VAULT_PORT"
ui = true
EOF
    chown "$VAULT_USER:$VAULT_USER" "$VAULT_CONFIG_FILE" || error_exit "Failed to set Vault config permissions"
}

# Configure iptables firewall rules for port 80
configure_firewall() {
    log "Configuring iptables rules for Vault on port $VAULT_PORT"
    iptables -A INPUT -p tcp --dport "$VAULT_PORT" -j ACCEPT || error_exit "Failed to add iptables rule for port $VAULT_PORT"
    iptables-save > /etc/iptables/rules.v4 || error_exit "Failed to save iptables rules"
    log "iptables rules configured to allow port $VAULT_PORT"
}

# Create systemd service for Vault with mlock capabilities
create_systemd_service() {
    log "Creating Vault systemd service"
    cat > /etc/systemd/system/vault.service << EOF
[Unit]
Description=HashiCorp Vault
After=network.target
Requires=network.target

[Service]
User=$VAULT_USER
Group=$VAULT_USER
ExecStart=$INSTALL_DIR/vault server -config=$VAULT_CONFIG_FILE
ExecReload=/bin/kill --signal HUP \$MAINPID
KillMode=process
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
CapabilityBoundingSet=CAP_IPC_LOCK
AmbientCapabilities=CAP_IPC_LOCK

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload || error_exit "Failed to reload systemd daemon"
    systemctl enable vault.service || error_exit "Failed to enable Vault service"
}

# Check if Vault service starts successfully
check_vault_service() {
    log "Starting Vault service"
    systemctl start vault.service
    sleep 5
    if ! systemctl is-active --quiet vault.service; then
        log "Vault service failed to start. Analyzing logs..."
        analyze_vault_logs
    else
        log "Vault service started successfully"
        echo "Vault service is running successfully."
    fi
}

# Analyze Vault logs for common issues and prompt for fixes
analyze_vault_logs() {
    log "Checking Vault logs for errors"
    JOURNAL_LOG=$(journalctl -u vault.service -n 50)

    # Check for storage backend issues
    if echo "$JOURNAL_LOG" | grep -q "storage configured to use \"file\""; then
        echo "Detected issue: Incorrect storage backend. Vault requires 'raft' or 'consul' instead of 'file'."
        read -p "Do you want to update the configuration to use 'raft' storage? (y/n): " update_storage
        if [ "$update_storage" = "y" ]; then
            update_storage_backend
            systemctl restart vault.service
            sleep 5
            if systemctl is-active --quiet vault.service; then
                log "Vault service started successfully after fixing storage backend"
                echo "Vault service is now running with 'raft' storage."
            else
                error_exit "Vault service still failed to start after storage backend fix"
            fi
        else
            log "User declined to update storage backend"
            echo "Storage backend not updated. Vault may not function correctly."
        fi
    fi

    # Check for mlock errors
    if echo "$JOURNAL_LOG" | grep -q "Failed to lock memory"; then
        echo "Detected issue: Vault cannot lock memory (mlock error)."
        echo "Options:"
        echo "1) Disable mlock (less secure)"
        echo "2) Adjust system limits in /etc/security/limits.conf (recommended, requires manual edit and reboot)"
        read -p "Do you want to disable mlock in the configuration? (y/n): " disable_mlock
        if [ "$disable_mlock" = "y" ]; then
            disable_mlock_config
            systemctl restart vault.service
            sleep 5
            if systemctl is-active --quiet vault.service; then
                log "Vault service started successfully after disabling mlock"
                echo "Vault service is now running with mlock disabled."
            else
                error_exit "Vault service still failed to start after disabling mlock"
            fi
        else
            log "User declined to disable mlock"
            echo "mlock not disabled. Please adjust system limits manually and restart the service."
            echo "Add to /etc/security/limits.conf:"
            echo "vault soft memlock unlimited"
            echo "vault hard memlock unlimited"
        fi
    fi

    # If no specific fix applied and service still down
    if ! systemctl is-active --quiet vault.service; then
        error_exit "Vault service failed to start. Check logs with 'journalctl -u vault.service' for details."
    fi
}

# Update storage backend to raft
update_storage_backend() {
    log "Updating storage backend to 'raft'"
    sed -i 's/storage "file"/storage "raft"/' "$VAULT_CONFIG_FILE" || {
        echo "storage \"raft\" {" > "$VAULT_CONFIG_FILE.tmp"
        echo "  path = \"$VAULT_DATA_DIR\"" >> "$VAULT_CONFIG_FILE.tmp"
        echo "  node_id = \"raft_node_1\"" >> "$VAULT_CONFIG_FILE.tmp"
        echo "}" >> "$VAULT_CONFIG_FILE.tmp"
        grep -v "storage \"file\"" "$VAULT_CONFIG_FILE" >> "$VAULT_CONFIG_FILE.tmp"
        mv "$VAULT_CONFIG_FILE.tmp" "$VAULT_CONFIG_FILE" || error_exit "Failed to update storage backend"
    }
    log "Storage backend updated to 'raft'"
}

# Disable mlock in configuration
disable_mlock_config() {
    log "Disabling mlock in Vault configuration"
    echo "disable_mlock = true" >> "$VAULT_CONFIG_FILE" || error_exit "Failed to disable mlock in config"
    log "mlock disabled in configuration"
}

# Initialize Vault
initialize_vault() {
    log "Initializing Vault"
    export VAULT_ADDR="$PROTOCOL://127.0.0.1:$VAULT_PORT"
    vault operator init -key-shares=1 -key-threshold=1 > /tmp/vault_init.txt || error_exit "Failed to initialize Vault"
    log "Vault initialized successfully"
    echo "Vault initialization details saved to /tmp/vault_init.txt"
    echo "Please store the unseal key and root token securely!"
}

# Prompt for initialization
prompt_for_initialization() {
    log "Prompting for Vault initialization"
    echo "Would you like to initialize Vault in production mode?"
    echo "1) Yes"
    echo "2) No"
    read -p "Select an option [1-2]: " init_choice
    case $init_choice in
        1)
            log "User chose to initialize Vault"
            initialize_vault
            return 0
            ;;
        2)
            log "User chose not to initialize Vault"
            return 0
            ;;
        *)
            error_exit "Invalid option selected"
            ;;
    esac
}

# Prompt for FQDN
prompt_for_fqdn() {
    log "Prompting for FQDN"
    read -p "Enter the Fully Qualified Domain Name (FQDN) for Vault access (e.g., vault.example.com): " FQDN
    if [ -z "$FQDN" ]; then
        error_exit "FQDN cannot be empty"
    fi
    log "FQDN set to $FQDN"
}

# Verify installation
verify_installation() {
    if command -v vault >/dev/null 2>&1; then
        INSTALLED_VERSION=$(vault --version | awk '{print $2}' | sed 's/v//')
        if [ "$INSTALLED_VERSION" = "$VAULT_VERSION" ]; then
            log "Vault version $VAULT_VERSION successfully installed"
            echo "Vault version $VAULT_VERSION installed successfully"
        else
            error_exit "Installed version ($INSTALLED_VERSION) does not match requested version ($VAULT_VERSION)"
        fi
    else
        error_exit "Vault installation failed - binary not found"
    fi
}

# Notify user on how to access Vault
notify_user() {
    log "Providing user notification for Vault access"
    ACCESS_URL="$PROTOCOL://$FQDN:$VAULT_PORT"
    cat << EOF | tee -a "$LOG_FILE"

============================================================
Vault Access Instructions
============================================================
Vault has been successfully installed at: $INSTALL_DIR/vault

To access Vault:
- Web Interface: $ACCESS_URL
- CLI: export VAULT_ADDR='$ACCESS_URL'

To manage Vault:
1. Start the service:
   $ systemctl start vault

2. Check status:
   $ systemctl status vault

3. If initialized, use the unseal key and root token from /tmp/vault_init.txt

For full documentation and configuration:
   Visit https://developer.hashicorp.com/vault/docs

Logs for this installation are available at: $LOG_FILE
============================================================
EOF
}

# Main execution
log "Script execution started"
if check_existing_vault; then
    handle_existing_vault
fi

install_vault
configure_vault_user
prompt_for_fqdn
create_vault_config
configure_firewall
create_systemd_service
verify_installation
check_vault_service  # Check if service starts, analyze logs and fix if needed
prompt_for_initialization
notify_user

log "Script execution completed successfully"
echo "Installation complete. Logs available at $LOG_FILE"