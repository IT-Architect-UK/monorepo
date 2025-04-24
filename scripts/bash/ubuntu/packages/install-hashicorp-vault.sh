#!/bin/bash

# This script installs HashiCorp Vault on an Ubuntu system, ensures Raft storage,
# removes request limiter settings, and handles initialization automatically.

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
VAULT_PORT=8200  # Default port, kept for clarity
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
[ -z "$VAULT_VERSION" ] && error_exit "Failed to fetch the latest Vault version"
log "Latest Vault version: $VAULT_VERSION"

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

# Handle existing Vault
handle_existing_vault() {
    log "Vault version $CURRENT_VERSION is already installed"
    echo "Existing Vault version $CURRENT_VERSION found"
    echo "1) Remove and install $VAULT_VERSION"
    echo "2) Upgrade to $VAULT_VERSION"
    echo "3) Exit"
    read -p "Select an option [1-3]: " choice
    case $choice in
        1) log "Removing existing Vault"; rm -f "$INSTALL_DIR/vault" || error_exit "Failed to remove Vault"; return 0;;
        2) log "Proceeding with upgrade"; return 0;;
        3) log "User chose to exit"; exit 0;;
        *) error_exit "Invalid option";;
    esac
}

# Install Vault
install_vault() {
    log "Creating temp directory: $TEMP_DIR"
    mkdir -p "$TEMP_DIR" || error_exit "Failed to create temp directory"

    log "Downloading Vault $VAULT_VERSION"
    curl -s -o "$TEMP_DIR/$VAULT_ZIP" "$VAULT_URL" || error_exit "Failed to download Vault"

    log "Unzipping Vault"
    unzip -o "$TEMP_DIR/$VAULT_ZIP" -d "$TEMP_DIR" || error_exit "Failed to unzip Vault"

    log "Installing Vault to $INSTALL_DIR"
    mv "$TEMP_DIR/vault" "$INSTALL_DIR/" && chmod +x "$INSTALL_DIR/vault" || error_exit "Failed to install Vault"

    log "Cleaning up"
    rm -rf "$TEMP_DIR" || log "Warning: Failed to clean up temp directory"
}

# Configure Vault user and directories
configure_vault_user() {
    log "Configuring Vault user and directories"
    id "$VAULT_USER" >/dev/null 2>&1 || useradd -r -s /bin/false "$VAULT_USER" || error_exit "Failed to create Vault user"
    mkdir -p "$VAULT_CONFIG_DIR" "$VAULT_DATA_DIR" || error_exit "Failed to create directories"
    chown -R "$VAULT_USER:$VAULT_USER" "$VAULT_CONFIG_DIR" "$VAULT_DATA_DIR" || error_exit "Failed to set permissions"
    chmod -R 750 "$VAULT_DATA_DIR" || error_exit "Failed to set data dir permissions"
}

# Prompt for FQDN
prompt_for_fqdn() {
    log "Prompting for FQDN"
    HOSTNAME=$(hostname)
    DOMAIN=$(grep -E '^(domain|search)' /etc/resolv.conf | awk '{print $2}' | head -1)
    DEFAULT_FQDN="${DOMAIN:+${HOSTNAME}.${DOMAIN}}"
    DEFAULT_FQDN=${DEFAULT_FQDN:-$HOSTNAME}
    read -e -p "Enter FQDN for Vault [default: $DEFAULT_FQDN]: " FQDN
    FQDN=${FQDN:-$DEFAULT_FQDN}
    [ -z "$FQDN" ] && error_exit "FQDN cannot be empty"
    log "FQDN set to $FQDN"
}

# Create Vault config with Raft storage, no request limiter
create_vault_config() {
    log "Creating Vault config file"
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
    chown "$VAULT_USER:$VAULT_USER" "$VAULT_CONFIG_FILE" && chmod 640 "$VAULT_CONFIG_FILE" || error_exit "Failed to set config permissions"
}

# Check for request limiter in config
check_request_limiter() {
    log "Checking for request limiter in $VAULT_CONFIG_FILE"
    if grep -i "limit_request_rate" "$VAULT_CONFIG_FILE" >/dev/null 2>&1; then
        log "Removing request limiter settings"
        sed -i '/limit_request_rate/d' "$VAULT_CONFIG_FILE" || error_exit "Failed to remove request limiter"
    fi
    log "No request limiter settings found or already removed"
}

# Configure firewall
configure_firewall() {
    log "Configuring iptables for port $VAULT_PORT"
    apt-get install -y iptables-persistent || error_exit "Failed to install iptables-persistent"
    iptables -A INPUT -p tcp --dport "$VAULT_PORT" -j ACCEPT || error_exit "Failed to add iptables rule"
    iptables-save > /etc/iptables/rules.v4 || error_exit "Failed to save iptables rules"
}

# Create systemd service with mlock fixes
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
LimitMEMLOCK=infinity
CapabilityBoundingSet=CAP_IPC_LOCK
AmbientCapabilities=CAP_IPC_LOCK

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload || error_exit "Failed to reload systemd"
    systemctl enable vault.service || error_exit "Failed to enable Vault service"
}

# Initialize Vault
initialize_vault() {
    log "Initializing Vault"
    export VAULT_ADDR="$PROTOCOL://127.0.0.1:$VAULT_PORT"
    systemctl start vault.service || error_exit "Failed to start Vault"
    sleep 5
    vault operator init -key-shares=1 -key-threshold=1 > /tmp/vault_init.txt || error_exit "Failed to initialize Vault"
    log "Vault initialized"
    echo "Vault initialization details in /tmp/vault_init.txt"
}

# Prompt for initialization
prompt_for_initialization() {
    log "Prompting for Vault initialization"
    echo "Initialize Vault in production mode?"
    echo "1) Yes"
    echo "2) No"
    read -p "Select an option [1-2]: " init_choice
    case $init_choice in
        1) log "User chose to initialize Vault"; initialize_vault; return 0;;
        2) log "User chose not to initialize"; return 0;;
        *) error_exit "Invalid option";;
    esac
}

# Verify installation and Raft storage
verify_installation() {
    log "Verifying installation"
    if command -v vault >/dev/null 2>&1; then
        INSTALLED_VERSION=$(vault --version | awk '{print $2}' | sed 's/v//')
        if [[ "$INSTALLED_VERSION" == "$VAULT_VERSION" ]]; then
            log "Vault $VAULT_VERSION installed"
            systemctl restart vault.service
            sleep 5
            if journalctl -u vault.service | grep -q "storage configured to use \"raft\""; then
                log "Raft storage confirmed"
            else
                error_exit "Raft storage not in use, check logs"
            fi
            echo "Vault $VAULT_VERSION installed successfully"
        else
            error_exit "Installed version ($INSTALLED_VERSION) mismatches $VAULT_VERSION"
        fi
    else
        error_exit "Vault installation failed - binary not found"
    fi
}

# Notify user
notify_user() {
    log "Providing Vault access instructions"
    ACCESS_URL="$PROTOCOL://$FQDN:$VAULT_PORT"
    cat << EOF | tee -a "$LOG_FILE"

============================================================
Vault Access Instructions
============================================================
Vault installed at: $INSTALL_DIR/vault
- Web Interface: $ACCESS_URL
- CLI: export VAULT_ADDR='$ACCESS_URL'

Manage Vault:
1. Start: systemctl start vault
2. Status: systemctl status vault
3. If initialized, see /tmp/vault_init.txt

Docs: https://developer.hashicorp.com/vault/docs
Logs: $LOG_FILE
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
check_request_limiter
configure_firewall
create_systemd_service
verify_installation
prompt_for_initialization
notify_user

log "Script completed successfully"
echo "Installation complete. Logs at $LOG_FILE"