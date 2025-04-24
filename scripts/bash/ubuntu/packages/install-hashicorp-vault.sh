#!/bin/bash

# This script installs HashiCorp Vault on an Ubuntu system, ensures it starts successfully,
# and handles initialization and permissions automatically.

# Check for root privileges and prompt for sudo if needed
if [ "$EUID" -ne 0 ]; then
    echo "This script requires root privileges. Please enter your sudo password."
    exec sudo "$0" "$@"
fi

# Variables
INSTALL_DIR="/usr/local/bin"
LOG_FILE="/var/log/vault_install.log"
TEMP_DIR="/tmp/vault_install"
VAULT_CONFIG_DIR="/etc/vault.d"
VAULT_DATA_DIR="/opt/vault/data"
VAULT_CONFIG_FILE="$VAULT_CONFIG_DIR/vault.hcl"
VAULT_USER="vault"
VAULT_PORT=8200
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

log "Starting Vault installation script"

# Check for required dependencies
log "Checking for required dependencies"
for cmd in curl unzip jq iptables ss; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log "Installing $cmd"
        apt-get update && apt-get install -y "$cmd" || error_exit "Failed to install $cmd"
    fi
done

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
    chmod -R 750 "$VAULT_DATA_DIR" || error_exit "Failed to set Vault data directory permissions"
}

# Prompt for FQDN with default value
prompt_for_fqdn() {
    log "Prompting for FQDN"
    HOSTNAME=$(hostname)
    DOMAIN=$(grep -E '^(domain|search)' /etc/resolv.conf | awk '{print $2}' | head -1)
    if [ -n "$DOMAIN" ]; then
        DEFAULT_FQDN="$HOSTNAME.$DOMAIN"
    else
        DEFAULT_FQDN="$HOSTNAME"
    fi
    read -e -p "Enter the Fully Qualified Domain Name (FQDN) for Vault access [default: $DEFAULT_FQDN]: " FQDN
    FQDN=${FQDN:-$DEFAULT_FQDN}
    if [ -z "$FQDN" ]; then
        error_exit "FQDN cannot be empty"
    fi
    log "FQDN set to $FQDN"
}

# Create Vault configuration for HTTP on port 8200
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
    chmod 640 "$VAULT_CONFIG_FILE" || error_exit "Failed to set Vault config file permissions"
}

# Configure iptables firewall rules for port 8200
configure_firewall() {
    log "Configuring iptables rules for Vault on port $VAULT_PORT"
    apt-get install -y iptables-persistent || error_exit "Failed to install iptables-persistent"
    iptables -A INPUT -p tcp --dport "$VAULT_PORT" -j ACCEPT || error_exit "Failed to add iptables rule for port $VAULT_PORT"
    iptables-save > /etc/iptables/rules.v4 || error_exit "Failed to save iptables rules"
    log "iptables rules configured to allow port $VAULT_PORT"
}

# Create systemd service for Vault
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

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload || error_exit "Failed to reload systemd daemon"
    systemctl enable vault.service || error_exit "Failed to enable Vault service"
}

# Initialize Vault
initialize_vault() {
    log "Initializing Vault"
    export VAULT_ADDR="$PROTOCOL://127.0.0.1:$VAULT_PORT"
    systemctl start vault.service || error_exit "Failed to start Vault service"
    sleep 5
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

# Verify installation
verify_installation() {
    if command -v vault >/dev/null 2>&1; then
        INSTALLED_VERSION=$(vault --version | awk '{print $2}' | sed 's/v//')
        if [[ "$INSTALLED_VERSION" == "$VAULT_VERSION" ]]; then
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
prompt_for_initialization
notify_user

log "Script execution completed successfully"
echo "Installation complete. Logs available at $LOG_FILE"