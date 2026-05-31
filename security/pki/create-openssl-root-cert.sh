#!/bin/bash

# Default values for certificate details and output directory
# Users can modify these defaults here for convenience
# or they will be prompted during execution.

DEFAULT_COUNTRY="GB"                          # Country Code
DEFAULT_STATE="Wales"                         # State or Province
DEFAULT_ORG="My Company"                      # Organization Name
DEFAULT_OU="Information Technology"           # Organizational Unit
DEFAULT_CN="RootCA"                           # Common Name
DEFAULT_OUTPUT_DIR="/opt/openssl"             # Output Directory for generated files

# This script generates a root CA certificate using OpenSSL on Ubuntu 24.
# It checks for OpenSSL, prompts the user for certificate details and output directory,
# and generates the root CA key and certificate in the specified location.
# All actions are logged to a file and displayed on the screen.
#
# Prerequisites:
#   - Ubuntu 24
#   - sudo privileges (for installing OpenSSL if missing and for directory operations)
#
# Output:
#   - root-ca.key: Root CA private key
#   - root-ca.crt: Root CA certificate
#   - generate_root_ca.log: Log file (in the current working directory)
#
# GitHub Repository:
#   This script is intended for use in a GitHub repository. Ensure proper
#   permissions are set (chmod +x generate_root_ca.sh) before execution.

# Set up logging to file and screen
log_file="./generate_root_ca.log"
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

# Prompt user for output directory with default
echo "Prompting user for output directory..."
read -p "Enter output directory [$DEFAULT_OUTPUT_DIR]: " output_dir
output_dir=${output_dir:-$DEFAULT_OUTPUT_DIR}
echo "Output directory set to: $output_dir"

# Create the output directory if it doesn't exist
if [ ! -d "$output_dir" ]; then
    echo "Creating output directory: $output_dir"
    sudo mkdir -p "$output_dir"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create output directory. Please check permissions."
        exit 1
    fi
else
    echo "Output directory already exists."
fi

# Check if output directory is writable
if [ ! -w "$output_dir" ]; then
    echo "Warning: Output directory is not writable. Using sudo for key and certificate generation."
    sudo_prefix="sudo"
else
    sudo_prefix=""
fi

# Collect certificate details with defaults
echo "Collecting certificate details from user..."
read -p "Country Code [$DEFAULT_COUNTRY]: " country
country=${country:-$DEFAULT_COUNTRY}
echo "Country Code set to: $country"

read -p "State [$DEFAULT_STATE]: " state
state=${state:-$DEFAULT_STATE}
echo "State set to: $state"

read -p "Organization Name [$DEFAULT_ORG]: " org
org=${org:-$DEFAULT_ORG}
echo "Organization Name set to: $org"

read -p "Organizational Unit [$DEFAULT_OU]: " ou
ou=${ou:-$DEFAULT_OU}
echo "Organizational Unit set to: $ou"

read -p "Common Name [$DEFAULT_CN]: " cn
cn=${cn:-$DEFAULT_CN}
echo "Common Name set to: $cn"

# Generate root CA key and certificate in the specified directory
echo "Generating 4096-bit RSA private key for root CA..."
$sudo_prefix openssl genrsa -out "$output_dir/root-ca.key" 4096
if [ $? -eq 0 ]; then
    echo "Root CA private key generated successfully: $output_dir/root-ca.key"
else
    echo "Error: Failed to generate root CA private key."
    exit 1
fi

echo "Generating self-signed root CA certificate (valid for 10 years)..."
$sudo_prefix openssl req -new -x509 -days 3650 -key "$output_dir/root-ca.key" -out "$output_dir/root-ca.crt" -subj "/C=$country/ST=$state/O=$org/OU=$ou/CN=$cn"
if [ $? -eq 0 ]; then
    echo "Root CA certificate generated successfully: $output_dir/root-ca.crt"
else
    echo "Error: Failed to generate root CA certificate."
    exit 1
fi

# Final summary
echo "Root CA generation completed successfully at $(date)"
echo "Generated files:"
echo "  - Private Key: $output_dir/root-ca.key"
echo "  - Certificate: $output_dir/root-ca.crt"
echo "  - Log File: $log_file"
echo "Script execution finished."