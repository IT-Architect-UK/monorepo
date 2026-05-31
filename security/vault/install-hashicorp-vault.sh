#!/bin/bash

# Log file location
LOG_FILE="/var/log/vault_install.log"

# Logging function to output to console and log file with timestamp
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    log "ERROR: This script requires root privileges. Please run with sudo."
    exit 1
fi

# Define default variables
INSTALL_DIR="/opt/vault"
VAULT_CONFIG_FILE="$INSTALL_DIR/vault-server.hcl"
CERT_FILE="$INSTALL_DIR/vault-cert.pem"
KEY_FILE="$INSTALL_DIR/vault-key.pem"
FQDN=$(hostname --fqdn)
IP_ADDRESS=$(hostname -I | awk '{print $1}')
VAULT_USER="vault"
VAULT_GROUP="vault"

# Prompt user for FQDN and installation directory
log "Prompting for server FQDN and installation directory..."
read -p "Enter the server's FQDN [default: $FQDN]: " INPUT_FQDN
FQDN=${INPUT_FQDN:-$FQDN}
log "Using FQDN: $FQDN"

read -p "Enter the installation directory [default: $INSTALL_DIR]: " INPUT_INSTALL_DIR
INSTALL_DIR=${INPUT_INSTALL_DIR:-$INSTALL_DIR}
log "Using installation directory: $INSTALL_DIR"

# Ensure installation directory exists
log "Creating installation directory if it doesn’t exist..."
mkdir -p "$INSTALL_DIR" || {
    log "ERROR: Failed to create directory $INSTALL_DIR"
    exit 1
}
chown root:root "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"

# Install prerequisites
log "Installing prerequisites (apt-transport-https, ca-certificates, curl, gnupg, lsb-release)..."
apt-get update | tee -a "$LOG_FILE"
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release | tee -a "$LOG_FILE" || {
    log "ERROR: Failed to install prerequisites"
    exit 1
}

# Create Vault user and group if they don’t exist
if ! id "$VAULT_USER" >/dev/null 2>&1; then
    log "Creating Vault user and group..."
    groupadd "$VAULT_GROUP" || {
        log "ERROR: Failed to create group $VAULT_GROUP"
        exit 1
    }
    useradd -r -s /bin/false -g "$VAULT_GROUP" "$VAULT_USER" || {
        log "ERROR: Failed to create user $VAULT_USER"
        exit 1
    }
    log "Vault user and group created successfully"
else
    log "Vault user and group already exist"
fi

# Add HashiCorp GPG key
log "Adding HashiCorp GPG key..."
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg || {
    log "ERROR: Failed to add HashiCorp GPG key"
    exit 1
}
log "HashiCorp GPG key added successfully"

# Add HashiCorp repository
log "Adding HashiCorp APT repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list || {
    log "ERROR: Failed to add HashiCorp repository"
    exit 1
}
log "HashiCorp repository added successfully"

# Install Vault (latest version from APT)
log "Updating APT and installing the latest version of Vault..."
apt-get update | tee -a "$LOG_FILE"
apt-get install -y vault | tee -a "$LOG_FILE" || {
    log "ERROR: Failed to install Vault"
    exit 1
}
log "Vault installed successfully"

# Verify Vault installation
if ! command -v vault >/dev/null 2>&1; then
    log "ERROR: Vault binary not found after installation"
    exit 1
else
    VAULT_VERSION=$(vault version | awk '{print $2}')
    log "Vault version installed: $VAULT_VERSION"
fi

# Generate self-signed certificate
log "Generating self-signed certificate with SANs for $FQDN and $IP_ADDRESS..."
openssl req -x509 -newkey rsa:4096 -sha256 -days 365 \
    -nodes -keyout "$KEY_FILE" -out "$CERT_FILE" \
    -subj "/CN=$FQDN" \
    -addext "subjectAltName=DNS:$FQDN,IP:$IP_ADDRESS" | tee -a "$LOG_FILE" || {
    log "ERROR: Failed to generate self-signed certificate"
    exit 1
}
log "Self-signed certificate generated successfully"

# Set certificate permissions
log "Setting certificate permissions..."
chown "$VAULT_USER:$VAULT_GROUP" "$CERT_FILE" "$KEY_FILE"
chmod 600 "$CERT_FILE" "$KEY_FILE"
log "Certificate permissions set"

# Create Vault configuration file with Raft storage
log "Creating Vault configuration file at $VAULT_CONFIG_FILE..."
cat > "$VAULT_CONFIG_FILE" << EOF
api_addr     = "https://$FQDN:8200"
cluster_addr = "https://$FQDN:8201"
ui           = true
disable_mlock = true

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "$CERT_FILE"
  tls_key_file  = "$KEY_FILE"
}

storage "raft" {
  path    = "$INSTALL_DIR/vault-data"
  node_id = "$(hostname)"
}
EOF
log "Vault configuration file created"

# Create Raft data directory and set permissions
log "Creating Raft data directory..."
mkdir -p "$INSTALL_DIR/vault-data" || {
    log "ERROR: Failed to create Raft data directory"
    exit 1
}
chown -R "$VAULT_USER:$VAULT_GROUP" "$INSTALL_DIR/vault-data"
chmod -R 750 "$INSTALL_DIR/vault-data"
log "Raft data directory created and permissions set"

# Set up systemd service
log "Setting up Vault systemd service..."
cat > /etc/systemd/system/vault.service << EOF
[Unit]
Description=HashiCorp Vault
After=network.target

[Service]
User=$VAULT_USER
Group=$VAULT_GROUP
ExecStart=/usr/bin/vault server -config=$VAULT_CONFIG_FILE
Restart=always
RestartSec=5
Capabilities=CAP_IPC_LOCK+ep
CapabilityBoundingSet=CAP_IPC_LOCK

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload || {
    log "ERROR: Failed to reload systemd daemon"
    exit 1
}
systemctl enable vault.service || {
    log "ERROR: Failed to enable Vault service"
    exit 1
}
log "Vault systemd service configured and enabled"

# Start Vault service
log "Starting Vault service..."
systemctl start vault.service || {
    log "ERROR: Failed to start Vault service"
    exit 1
}
sleep 5
if ! systemctl is-active --quiet vault.service; then
    log "ERROR: Vault service is not active. Check logs with 'journalctl -u vault.service'"
    exit 1
fi
log "Vault service started successfully"

# Set environment variables for Vault CLI
export VAULT_ADDR="https://$FQDN:8200"
export VAULT_SKIP_VERIFY=true
log "Vault environment variables set: VAULT_ADDR=$VAULT_ADDR, VAULT_SKIP_VERIFY=true"

# Initialize Vault
log "Initializing Vault..."
INIT_OUTPUT=$(vault operator init -key-shares=1 -key-threshold=1 2>&1) || {
    log "ERROR: Failed to initialize Vault: $INIT_OUTPUT"
    exit 1
}
UNSEAL_KEY=$(echo "$INIT_OUTPUT" | grep "Unseal Key 1:" | awk '{print $4}')
ROOT_TOKEN=$(echo "$INIT_OUTPUT" | grep "Initial Root Token:" | awk '{print $4}')
log "Vault initialized. Unseal Key: $UNSEAL_KEY, Root Token: $ROOT_TOKEN"

KEY_TOKEN_FILE="$INSTALL_DIR/install-key-token.txt"
echo "Unseal Key: $UNSEAL_KEY" > "$KEY_TOKEN_FILE"
echo "Root Token: $ROOT_TOKEN" >> "$KEY_TOKEN_FILE"
chown root:root "$KEY_TOKEN_FILE"
chmod 600 "$KEY_TOKEN_FILE"
log "Unseal Key and Root Token saved to $KEY_TOKEN_FILE"

# Unseal Vault
log "Unsealing Vault..."
vault operator unseal "$UNSEAL_KEY" | tee -a "$LOG_FILE" || {
    log "ERROR: Failed to unseal Vault"
    exit 1
}
log "Vault unsealed successfully"

# Final instructions for the user
log "Vault setup complete!"
echo "Vault is running at $VAULT_ADDR"
echo "Unseal Key: $UNSEAL_KEY"
echo "Root Token: $ROOT_TOKEN"
echo "Unseal Key and Root Token saved to $KEY_TOKEN_FILE"
echo "Delete $KEY_TOKEN_FILE as soon you have stored the keys securely."
echo "Please store the unseal key and root token securely!"
echo "To log in, run: export VAULT_ADDR='https://$FQDN:8200' && vault login $ROOT_TOKEN"