#!/bin/bash

# generate_root_ca.sh
#
# This script generates a root CA certificate using OpenSSL on Ubuntu 24.
# It checks for OpenSSL, prompts the user for certificate details, and generates
# the root CA key and certificate. All actions are logged to a file and displayed
# on the screen.
#
# Usage:
#   ./generate_root_ca.sh
#
# Prerequisites:
#   - Ubuntu 24
#   - sudo privileges (for installing OpenSSL if missing)
#
# Defaults:
#   - Country Code: GB
#   - State: Wales
#   - Organization Name: My Company
#   - Organizational Unit: Information Technology
#   - Common Name: RootCA
#
# Excluded Fields:
#   - Email
#   - Locality
#
# Output:
#   - root-ca.key: Root CA private key
#   - root-ca.crt: Root CA certificate
#   - generate_root_ca.log: Log file
#
# GitHub Repository:
#   This script is intended for use in a GitHub repository. Ensure proper
#   permissions are set (chmod +x generate_root_ca.sh) before execution.

# Set up logging to file and screen
log_file="generate_root_ca.log"
exec > >(tee -a "$log_file") 2>&1

echo "Starting root CA certificate generation script at $(date)"

# Check if OpenSSL is installed
echo "Checking for OpenSSL installation..."
if ! command -v openssl &> /dev/null; then
    echo "OpenSSL not found. Attempting to install OpenSSL..."
    sudo apt-get update && sudo apt-get install -y openssl
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install OpenSSL. Please install it manually and retry."
        exit 1
    else
        echo "OpenSSL installed successfully."
    fi
else
    echo "OpenSSL is already installed."
fi

# Prompt user to confirm root certificate generation
echo "Prompting user for confirmation..."
read -p "Do you want to generate a root certificate? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "User chose not to generate a root certificate. Exiting script at $(date)."
    exit 0
else
    echo "User confirmed generation of root certificate."
fi

# Collect certificate details with defaults
echo "Collecting certificate details from user..."
read -p "Country Code [GB]: " country
country=${country:-GB}
echo "Country Code set to: $country"

read -p "State [Wales]: " state
state=${state:-Wales}
echo "State set to: $state"

read -p "Organization Name [My Company]: " org
org=${org:-My Company}
echo "Organization Name set to: $org"

read -p "Organizational Unit [Information Technology]: " ou
ou=${ou:-Information Technology}
echo "Organizational Unit set to: $ou"

read -p "Common Name [RootCA]: " cn
cn=${cn:-RootCA}
echo "Common Name set to: $cn"

# Generate root CA key and certificate
echo "Generating 4096-bit RSA private key for root CA..."
openssl genrsa -out root-ca.key 4096
if [ $? -eq 0 ]; then
    echo "Root CA private key generated successfully: root-ca.key"
else
    echo "Error: Failed to generate root CA private key."
    exit 1
fi

echo "Generating self-signed root CA certificate (valid for 10 years)..."
openssl req -new -x509 -days 3650 -key root-ca.key -out root-ca.crt -subj "/C=$country/ST=$state/O=$org/OU=$ou/CN=$cn"
if [ $? -eq 0 ]; then
    echo "Root CA certificate generated successfully: root-ca.crt"
else
    echo "Error: Failed to generate root CA certificate."
    exit 1
fi

# Final summary
echo "Root CA generation completed successfully at $(date)"
echo "Generated files:"
echo "  - Private Key: root-ca.key"
echo "  - Certificate: root-ca.crt"
echo "  - Log File: $log_file"
echo "Script execution finished."