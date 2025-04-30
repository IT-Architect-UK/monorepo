#!/bin/bash

# Script to install the latest Bacula on Ubuntu 24.04 with verbose logging and existing installation detection

# Variables
LOG_FILE="/var/log/bacula_install_$(date +%Y%m%d_%H%M%S).log"
BACULA_USER="bacula"
BACULA_GROUP="bacula"
BACKUP_DIR="/bacula/backup"
RESTORE_DIR="/bacula/restore"
CONFIG_DIR="/etc/bacula"
POSTGRESQL_VERSION="16"  # Ubuntu 24.04 default PostgreSQL version
BACULA_PACKAGE="bacula"
POSTGRESQL_PACKAGE="postgresql"
BACULA_SERVICES=("bacula-dir" "bacula-sd" "bacula-fd")
MIN_RAM="2G"  # Minimum RAM recommended for Bacula server
VERBOSE=true  # Enable verbose logging
APT_TIMEOUT=600  # Timeout for apt-get install in seconds (10 minutes)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

# Function to log messages
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
    if [ "$VERBOSE" = true ]; then
        echo -e "${YELLOW}[$timestamp] $message${NC}"
    fi
}

# Function to check if script is run as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_message "ERROR: This script must be run as root."
        exit 1
    fi
    log_message "Running as root."
}

# Function to check system requirements
check_requirements() {
    log_message "Checking system requirements..."
    local total_ram=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$total_ram" -lt 2048 ]; then
        log_message "WARNING: System has less than $MIN_RAM RAM ($total_ram MB detected). Bacula may require more resources."
    else
        log_message "RAM check passed: $total_ram MB detected."
    fi
    # Check disk space
    local disk_space=$(df -m / | tail -1 | awk '{print $4}')
    if [ "$disk_space" -lt 2048 ]; then
        log_message "WARNING: Less than 2GB free disk space on / ($disk_space MB detected). Bacula installation may fail."
    else
        log_message "Disk space check passed: $disk_space MB free on /."
    fi
}

# Function to detect existing Bacula installation
check_existing_install() {
    log_message "Checking for existing Bacula installation..."
    if dpkg -l | grep -q "$BACULA_PACKAGE"; then
        log_message "${RED}WARNING: Bacula is already installed on this system!${NC}"
        log_message "Existing Bacula packages:"
        dpkg -l | grep bacula | tee -a "$LOG_FILE"
        read -p "Do you want to continue with the installation? This may overwrite existing configurations! (y/N): " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log_message "User chose to exit due to existing Bacula installation."
            exit 0
        else
            log_message "User confirmed to proceed with installation despite existing Bacula."
        fi
    else
        log_message "No existing Bacula installation detected."
    fi
}

# Function to set up logging
setup_logging() {
    log_message "Setting up logging..."
    touch "$LOG_FILE" || {
        echo "ERROR: Cannot create log file at $LOG_FILE"
        exit 1
    }
    chmod 644 "$LOG_FILE"
    log_message "Logging initialized to $LOG_FILE"
}

# Function to check for apt locks
check_apt_locks() {
    log_message "Checking for apt locks..."
    if pgrep -x "apt|apt-get" > /dev/null; then
        log_message "ERROR: Another apt process is running. Please wait or terminate it."
        exit 1
    fi
    if [ -f /var/lib/dpkg/lock-frontend ]; then
        log_message "WARNING: Dpkg lock detected. Attempting to clear..."
        rm -f /var/lib/dpkg/lock-frontend
        rm -f /var/cache/apt/archives/lock
        dpkg --configure -a >> "$LOG_FILE" 2>&1
    fi
    log_message "No apt locks detected."
}

# Function to update system and install dependencies
install_dependencies() {
    log_message "Updating package lists..."
    timeout "$APT_TIMEOUT" apt-get update -y >> "$LOG_FILE" 2>&1 || {
        log_message "ERROR: Failed to update package lists. Check network or repositories."
        exit 1
    }
    log_message "Installing PostgreSQL..."
    timeout "$APT_TIMEOUT" apt-get install -y "$POSTGRESQL_PACKAGE" >> "$LOG_FILE" 2>&1 || {
        log_message "ERROR: Failed to install PostgreSQL."
        exit 1
    }
    log_message "PostgreSQL installed successfully."
}

# Function to install Bacula
install_bacula() {
    log_message "Installing the latest Bacula package..."
    timeout "$APT_TIMEOUT" apt-get install -y --no-install-recommends "$BACULA_PACKAGE" >> "$LOG_FILE" 2>&1 || {
        log_message "ERROR: Failed to install Bacula. Check $LOG_FILE for details."
        exit 1
    }
    # Log the installed Bacula version
    local installed_version=$(dpkg -l | grep bacula | awk '{print $3}' | head -1)
    log_message "Bacula installed successfully. Installed version: $installed_version"
}

# Function to configure Bacula user and directories
configure_bacula() {
    log_message "Configuring Bacula user and directories..."
    # Create backup and restore directories
    mkdir -p "$BACKUP_DIR" "$RESTORE_DIR" >> "$LOG_FILE" 2>&1 || {
        log_message "ERROR: Failed to create directories $BACKUP_DIR or $RESTORE_DIR."
        exit 1
    }
    # Set ownership and permissions
    chown -R "$BACULA_USER:$BACULA_GROUP" "$BACKUP_DIR" "$RESTORE_DIR" >> "$LOG_FILE" 2>&1
    chmod -R 700 "$BACKUP_DIR" "$RESTORE_DIR" >> "$LOG_FILE" 2>&1
    log_message "Backup and restore directories configured."
}

# Function to configure PostgreSQL for Bacula
configure_postgresql() {
    log_message "Configuring PostgreSQL for Bacula..."
    # Run Bacula database creation scripts
    su - postgres -c "/usr/share/bacula-director/create_postgresql_database" >> "$LOG_FILE" 2>&1 || {
        log_message "ERROR: Failed to create Bacula database."
        exit 1
    }
    su - postgres -c "/usr/share/bacula-director/make_postgresql_tables" >> "$LOG_FILE" 2>&1 || {
        log_message "ERROR: Failed to create Bacula tables."
        exit 1
    }
    su - postgres -c "/usr 0.
    log_message "Bacula installation verified successfully."
}

# Main execution
Starting Bacula installation script on Ubuntu 24.04...

check_root
setup_logging
check_requirements
check_existing_install
check_apt_locks
install_dependencies
install_bacula
configure_bacula
configure_postgresql
restar_services
verify_installation

log_message "${GREEN}Bacula installation completed successfully!${NC}"
log_message "Log file: $LOG_FILE"
log_message "Next steps:"
log_message "1. Edit configuration files in $CONFIG_DIR to set up backup jobs."
log_message "2. Use 'bconsole' to manage Bacula and test backups."
log_message "3. Check the official Bacula documentation for advanced configuration: https://www.bacula.org"

exit 0