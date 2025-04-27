#!/bin/bash

: '
.SYNOPSIS
This script signs a Sub CA Certificate Signing Request (CSR) using an OpenSSL-based Root CA.

.DESCRIPTION
The script performs the following actions:
- Prompts the user for paths to the Root CA key, certificate, Sub CA CSR, and output certificate.
- Verifies the existence and validity of the provided files.
- Creates an OpenSSL configuration file with Sub CA extensions.
- Signs the CSR with the Root CA to generate a Sub CA certificate.
- Verifies the signed certificate.
- Logs all actions to a file and displays them on the screen.

.NOTES
Version:            1.1
Author:             Darren Pilkington
Modification Date:  27-04-2025
Prerequisites:      OpenSSL installed, Root CA key and certificate, Sub CA CSR
GitHub:             https://github.com/IT-Architect-UK/monorepo
'

# Default log file in the current working directory
DEFAULT_LOG_FILE="./sign_sub_ca-$(date '+%Y%m%d').log"

# Function to write log with timestamp
write_log() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

# Prompt for log file path
echo "Prompting for log file path..."
read -p "Enter log file path [$DEFAULT_LOG_FILE]: " LOG_FILE
LOG_FILE=${LOG_FILE:-$DEFAULT_LOG_FILE}
write_log "Log file set to: $LOG_FILE"

# Ensure log file directory exists
LOG_DIR=$(dirname "$LOG_FILE")
if [ ! -d "$LOG_DIR" ]; then
    write_log "Creating log directory: $LOG_DIR"
    mkdir -p "$LOG_DIR" || { write_log "Error: Failed to create log directory $LOG_DIR."; exit 1; }
fi

# Set up logging to file and screen
exec > >(tee -a "$LOG_FILE") 2>&1
write_log "Starting Sub CA CSR signing script at $(date)"

# Check for OpenSSL
write_log "Checking for OpenSSL installation..."
if ! command -v openssl &> /dev/null; then
    write_log "Error: OpenSSL not found. Please install OpenSSL and retry."
    exit 1
fi
write_log "OpenSSL is installed."

# Prompt for file paths
write_log "Prompting for file paths..."

read -p "Enter path to Root CA private key: " ROOT_CA_KEY
if [ ! -f "$ROOT_CA_KEY" ]; then
    write_log "Error: Root CA private key $ROOT_CA_KEY does not exist."
    exit 1
fi
write_log "Root CA private key set to: $ROOT_CA_KEY"

read -p "Enter path to Root CA certificate: " ROOT_CA_CERT
if [ ! -f "$ROOT_CA_CERT" ]; then
    write_log "Error: Root CA certificate $ROOT_CA_CERT does not exist."
    exit 1
fi
write_log "Root CA certificate set to: $ROOT_CA_CERT"

read -p "Enter path to Sub CA CSR: " SUB_CA_CSR
if [ ! -f "$SUB_CA_CSR" ]; then
    write_log "Error: Sub CA CSR $SUB_CA_CSR does not exist."
    exit 1
fi
write_log "Sub CA CSR set to: $SUB_CA_CSR"

read -p "Enter output path for signed Sub CA certificate: " SUB_CA_CERT
SUB_CA_DIR=$(dirname "$SUB_CA_CERT")
if [ ! -d "$SUB_CA_DIR" ]; then
    write_log "Creating output directory: $SUB_CA_DIR"
    mkdir -p "$SUB_CA_DIR" || { write_log "Error: Failed to create output directory $SUB_CA_DIR."; exit 1; }
fi
write_log "Output Sub CA certificate set to: $SUB_CA_CERT"

# Verify CSR validity
write_log "Verifying Sub CA CSR..."
if ! openssl req -in "$SUB_CA_CSR" -noout -text >/dev/null 2>&1; then
    write_log "Error: Invalid Sub CA CSR."
    exit 1
fi
write_log "Sub CA CSR is valid."

# Check if output directory is writable, use sudo if needed
if [ ! -w "$SUB_CA_DIR" ]; then
    write_log "Warning: Output directory is not writable. Using sudo for certificate generation."
    sudo_prefix="sudo"
else
    sudo_prefix=""
fi

# Create temporary OpenSSL configuration file for Sub CA extensions
write_log "Creating OpenSSL configuration for Sub CA extensions..."
temp_conf=$(mktemp)
cat > "$temp_conf" <<EOF
[ v3_ca ]
basicConstraints = critical,CA:TRUE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

# Sign the CSR
write_log "Signing Sub CA CSR with Root CA..."
if ! $sudo_prefix openssl x509 -req -in "$SUB_CA_CSR" -CA "$ROOT_CA_CERT" -CAkey "$ROOT_CA_KEY" -CAcreateserial -out "$SUB_CA_CERT" -days 1825 -sha256 -extfile "$temp_conf" -extensions v3_ca; then
    write_log "Error: Failed to sign Sub CA CSR."
    rm -f "$temp_conf"
    exit 1
fi
write_log "Sub CA certificate generated successfully: $SUB_CA_CERT"

# Clean up temporary configuration file
rm -f "$temp_conf"
write_log "Cleaned up temporary configuration file."

# Verify the signed certificate
write_log "Verifying signed Sub CA certificate..."
if ! openssl verify -CAfile "$ROOT_CA_CERT" "$SUB_CA_CERT" >/dev/null 2>&1; then
    write_log "Error: Signed Sub CA certificate verification failed."
    exit 1
fi
write_log "Signed Sub CA certificate verified successfully."

# Display certificate details
write_log "Displaying Sub CA certificate details..."
openssl x509 -in "$SUB_CA_CERT" -text -noout

# Final summary
write_log "Sub CA CSR signing completed successfully at $(date)"
write_log "Generated files:"
write_log "  - Sub CA Certificate: $SUB_CA_CERT"
write_log "  - Log File: $LOG_FILE"
write_log "Next steps: Import $SUB_CA_CERT into Vault using the Vault CLI or API (e.g., vault write pki/intermediate/set-signed certificate=@$SUB_CA_CERT)."