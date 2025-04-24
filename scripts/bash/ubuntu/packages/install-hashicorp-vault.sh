#!/bin/bash

# This script installs HashiCorp Vault on an Ubuntu system using HTTP on port 8200.
# It ensures secure configurations, uses best practices, and resumes after reboots if needed.

# Check if running in bash
if [ -z "$BASH_VERSION" ]; then
    echo "Error: This script must be run with bash."
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
VAULT_PORT=8200
PROTOCOL="http"
STATE_FILE="/var/run/vault_install_state"
RESUME_SERVICE="/etc/systemd/system/vault-install-resume.service"

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
    rm -f "$STATE_FILE"
    systemctl disable vault-install-resume.service >/dev/null 2>&1
    systemctl stop vault-install-resume.service >/dev/null 2>&1
    rm -f "$RESUME_SERVICE"
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

# Function to create resume service
create_resume_service() {
    log "Creating systemd service to resume script after reboot"
    cat > "$RESUME_SERVICE" << EOF
[Unit]
Description=Resume Vault Installation After Reboot
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash $0 --resume
RemainAfterExit=no
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload || error_exit "Failed to reload systemd daemon for resume service"
    systemctl enable vault-install-resume.service || error_exit "Failed to enable resume service"
}

# Check if resuming after reboot
if [ "$1" = "--resume" ]; then
    log "Resuming installation after reboot"
    if [ ! -f "$STATE_FILE" ]; then
        error_exit "State file not found, cannot resume installation"
    fi
    STATE=$(cat "$STATE_FILE")
    log "Resuming from state: $STATE"
else
    STATE="start"
fi

# Configure memory lock limits for vault user
configure_mlock_limits() {
    if [ "$STATE" != "post-reboot" ]; then
        log "Configuring memory lock limits for vault user"
        if ! grep -q "vault.*memlock" /etc/security/limits.conf; then
            echo "vault soft memlock unlimited" | tee -a /etc/security/limits.conf
            echo "vault hard memlock unlimited" | tee -a /etc/security/limits.conf
            log "Memory lock limits configured. Reboot required."
            echo "post-reboot" > "$STATE_FILE"
            create_resume_service
            log "Rebooting system..."
            reboot
            exit 0
        else
            log "Memory lock limits already configured."
        fi
    fi
}

# Fetch the latest Vault version
fetch_vault_version() {
    log "Fetching the latest Vault version"
    VAULT_VERSION=$(curl -s https://releases.hashicorp.com/vault/index.json | jq -r '.versions | keys[]' | sort -V | tail -n 1)
    if [ -z "$VAULT_VERSION" ]; then
        error_exit "Failed to fetch the latest Vault version"
    fi
    log "Latest Vault version: $VAULT_VERSION"
    VAULT_ZIP="vault_${VAULT_VERSION}_linux_amd64.zip"
    VAULT_URL="https://releases.hashicorp.com/vault/${VAULT_VERSION}/${VAULT_ZIP}"
}

# Install Vault
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

# Create Vault configuration with raft storage
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

# Configure iptables firewall rules
configure_firewall() {
    log "Configuring iptables rules for Vault on port $VAULT_PORT"
    apt-get install -y iptables-persistent || error_exit "Failed to install iptables-persistent"
    iptables -A INPUT -p tcp --dport "$VAULT_PORT" -j ACCEPT || error_exit "Failed to add iptables rule"
    iptables-save > /etc/iptables/rules.v4 || error_exit "Failed to save iptables rules"
}

# Create systemd service with CAP_IPC_LOCK
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

# Check Vault service
check_vault_service() {
    log "Starting Vault service"
    systemctl start vault.service
    sleep 5
    if systemctl is-active --quiet vault.service; then
        log "Vault service started successfully"
        echo "Vault service is running successfully."
    else
        error_exit "Vault service failed to start. Check logs with 'journalctl -u vault.service'"
    fi
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

# Notify user
notify_user() {
    log "Providing user notification"
    ACCESS_URL="$PROTOCOL://$FQDN:$VAULT_PORT"
    cat << EOF | tee -a "$LOG_FILE"

============================================================
Vault Installation Complete
============================================================
Vault is installed at: $INSTALL_DIR/vault
Access it via:
- Web Interface: $ACCESS_URL
- CLI: export VAULT_ADDR='$ACCESS_URL'

Manage Vault:
1. Start: systemctl start vault
2. Status: systemctl status vault

Logs: $LOG_FILE
Docs: https://developer.hashicorp.com/vault/docs
============================================================
EOF
}

# Main execution
case "$STATE" in
    "start")
        configure_mlock_limits
        fetch_vault_version
        install_vault
        configure_vault_user
        prompt_for_fqdn
        create_vault_config
        configure_firewall
        create_systemd_service
        verify_installation
        check_vault_service
        notify_user
        ;;
    "post-reboot")
        fetch_vault_version
        install_vault
        configure_vault_user
        prompt_for_fqdn
        create_vault_config
        configure_firewall
        create_systemd_service
        verify_installation
        check_vault_service
        notify_user
        ;;
    *)
        error_exit "Invalid state: $STATE"
        ;;
esac

# Cleanup
rm -f "$STATE_FILE"
systemctl disable vault-install-resume.service >/dev/null 2>&1
systemctl stop vault-install-resume.service >/dev/null 2>&1
rm -f "$RESUME_SERVICE"

log "Script execution completed successfully"
echo "Installation complete. Logs at $LOG_FILE"