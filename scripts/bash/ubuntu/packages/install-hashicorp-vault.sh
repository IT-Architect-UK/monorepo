#!/bin/bash

# Script to install and configure HashiCorp Vault with Raft storage and self-signed certificate

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "This script requires root privileges. Please run with sudo."
    exit 1
fi

# Variables
INSTALL_DIR="/tmp"  # Default installation directory, can be modified
VAULT_CONFIG_FILE="$INSTALL_DIR/vault-server.hcl"
CERT_FILE="$INSTALL_DIR/vault-cert.pem"
KEY_FILE="$INSTALL_DIR/vault-key.pem"
FQDN=$(hostname --fqdn)
IP_ADDRESS=$(hostname -I | awk '{print $1}')

# Prompt for FQDN
read -p "Enter the server's FQDN [default: $FQDN]: " INPUT_FQDN
FQDN=${INPUT_FQDN:-$FQDN}

# Prompt for installation directory
read -p "Enter the installation directory [default: $INSTALL_DIR]: " INPUT_INSTALL_DIR
INSTALL_DIR=${INPUT_INSTALL_DIR:-$INSTALL_DIR}

# Ensure installation directory exists
mkdir -p "$INSTALL_DIR"

# Install prerequisites
apt-get update
apt-get install -y openssl curl jq

# Generate self-signed certificate with FQDN and IP as SANs
openssl req -x509 -newkey rsa:4096 -sha256 -days 365 \
    -nodes -keyout "$KEY_FILE" -out "$CERT_FILE" \
    -subj "/CN=localhost" \
    -addext "subjectAltName=DNS:localhost,DNS:$FQDN,IP:127.0.0.1,IP:$IP_ADDRESS"

# Create Vault configuration file
cat > "$VAULT_CONFIG_FILE" << EOF
api_addr                = "https://127.0.0.1:8200"
cluster_addr            = "https://127.0.0.1:8201"
cluster_name            = "learn-vault-cluster"
disable_mlock           = true
ui                      = true

listener "tcp" {
  address       = "127.0.0.1:8200"
  tls_cert_file = "$CERT_FILE"
  tls_key_file  = "$KEY_FILE"
}

backend "raft" {
  path    = "$INSTALL_DIR/vault-data"
  node_id = "$(hostname)"
}
EOF

# Create Raft data directory
mkdir -p "$INSTALL_DIR/vault-data"

# Set permissions
chown -R vault:vault "$INSTALL_DIR/vault-data"
chmod -R 750 "$INSTALL_DIR/vault-data"

# Start Vault server in the background
vault server -config="$VAULT_CONFIG_FILE" &

# Wait for Vault to start
sleep 5

# Set environment variables
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_SKIP_VERIFY=true

# Initialize Vault
INIT_OUTPUT=$(vault operator init -key-shares=1 -key-threshold=1)

# Extract unseal key and root token
UNSEAL_KEY=$(echo "$INIT_OUTPUT" | grep "Unseal Key 1:" | awk '{print $4}')
ROOT_TOKEN=$(echo "$INIT_OUTPUT" | grep "Initial Root Token:" | awk '{print $4}')

# Display initialization info
echo "Vault initialized successfully."
echo "Unseal Key 1: $UNSEAL_KEY"
echo "Initial Root Token: $ROOT_TOKEN"
echo "Please make a note of the unseal key and root token and store them securely!"

# Prompt to unseal Vault
echo "Unsealing Vault..."
vault operator unseal "$UNSEAL_KEY"

# Check Vault status
vault status

# Prompt for login
echo "Login to Vault using the root token:"
vault login "$ROOT_TOKEN"

echo "Vault setup complete. You can access the UI at $VAULT_ADDR"