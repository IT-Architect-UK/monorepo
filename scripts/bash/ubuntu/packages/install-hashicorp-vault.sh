#!/bin/bash

# Introduction
# This script installs HashiCorp Vault on an Ubuntu system. It:
# - Checks for existing Vault installations
# - Offers to remove or upgrade existing versions
# - Installs the specified version of Vault
# - Configures logging for all operations
# - Is designed for reliability and ease of use in a GitHub repository

# Variables (modify these as needed)
VAULT_VERSION="1.17.2"  # Desired Vault version
INSTALL_DIR="/usr/local/bin"  # Installation directory
LOG_FILE="/var/log/vault_install.log"  # Log file location
VAULT_ZIP="vault_${VAULT_VERSION}_linux_amd64.zip"  # Vault zip file name
VAULT_URL="https://releases.hashicorp.com/vault/${VAULT_VERSION}/${VAULT_ZIP}"  # Download URL
TEMP_DIR="/tmp/vault_install"  # Temporary directory for installation

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $1" | tee -a "$LOG_FILE"
}

# Error handling function
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error_exit "This script must be run as root"
fi

log "Starting Vault installation script"

# Check for required dependencies
log "Checking for required dependencies"
for cmd in curl unzip jq; do
    if ! command -v "$cmd" &> /dev/null; then
        log "Installing $cmd"
        apt-get update && apt-get install -y "$cmd" || error_exit "Failed to install $cmd"
    fi
done

# Check for existing Vault installation
check_existing_vault() {
    if command -v vault &> /dev/null; then
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
    echo "1) Remove and install new version ($VAULT_VERSION)"
    echo "2) Upgrade to version $VAULT_VERSION"
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

# Verify installation
verify_installation() {
    if command -v vault &> /dev/null; then
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

# Main execution
log "Script execution started"
if check_existing_vault; then
    handle_existing_vault
fi

install_vault
verify_installation

log "Script execution completed successfully"
echo "Installation complete. Logs available at $LOG_FILE"