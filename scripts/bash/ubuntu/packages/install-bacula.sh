#!/bin/bash

# Script to install the latest Bacula on Ubuntu 24.04 with latest PostgreSQL and full terminal output

# Variables
LOG_FILE="/var/log/bacula_install_$(date +%Y%m%d_%H%M%S).log"
BACKUP_DIR="/bacula/backup"
RESTORE_DIR="/bacula/restore"
CONFIG_DIR="/etc/bacula"
BACULA_PACKAGE="bacula"
POSTGRESQL_PACKAGE="postgresql"
BACULA_SERVICES=("bacula-dir" "bacula-sd" "bacula-fd")
MIN_RAM="2G"  # Minimum RAM recommended for Bacula server
VERBOSE=true  # Enable verbose logging
APT_TIMEOUT=900  # Timeout for apt-get install in seconds (15 minutes)
SERVICE_TIMEOUT=30  # Timeout for service commands in seconds
PG_PORT=5432  # Default PostgreSQL port
DIR_OWNER="root"  # Owner for backup/restore directories
DIR_GROUP="root"  # Group for backup/restore directories

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

# Function to log messages
log_message() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOG_FILE"
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
        echo "ERROR: Cannot create log file at $LOG_FILE" | tee -a "$LOG_FILE"
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
        dpkg --configure -a | tee -a "$LOG_FILE"
    fi
    log_message "No apt locks detected."
}

# Function to check PostgreSQL port
check_postgresql_port() {
    log_message "Checking if PostgreSQL port $PG_PORT is in use..."
    if netstat -tuln | grep -q ":$PG_PORT "; then
        log_message "ERROR: Port $PG_PORT is already in use. Stop the conflicting service or change the PostgreSQL port."
        exit 1
    fi
    log_message "Port $PG_PORT is free."
}

# Function to add PostgreSQL repository
add_postgresql_repo() {
    log_message "Adding official PostgreSQL repository..."
    # Install prerequisites
    apt-get install -y wget ca-certificates | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to install wget and ca-certificates."
        exit 1
    }
    # Add PostgreSQL APT repository
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to add PostgreSQL repository key."
        exit 1
    }
    echo "deb http://apt.postgresql.org/pub/repos/apt/ noble-pgdg main" > /etc/apt/sources.list.d/pgdg.list
    apt-get update -y | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to update package lists after adding PostgreSQL repository."
        exit 1
    }
    log_message "PostgreSQL repository added successfully."
}

# Function to log system state
log_system_state() {
    log_message "Logging system state..."
    log_message "Disk usage:"
    df -h / | tee -a "$LOG_FILE"
    log_message "Memory usage:"
    free -h | tee -a "$LOG_FILE"
    log_message "Top processes:"
    top -bn1 | head -n 10 | tee -a "$LOG_FILE"
    log_message "System state logged."
}

# Function to update system and install dependencies
install_dependencies() {
    log_message "Starting package list update..."
    timeout -k 10 "$APT_TIMEOUT" apt-get update -y | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to update package lists. Check network or repositories."
        exit 1
    }
    log_message "Package list update completed."
    log_message "Masking PostgreSQL service to prevent startup during install..."
    systemctl mask postgresql | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to mask PostgreSQL service."
        exit 1
    }
    log_message "Starting PostgreSQL installation..."
    log_system_state
    timeout -k 10 "$APT_TIMEOUT" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$POSTGRESQL_PACKAGE" | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to install PostgreSQL."
        exit 1
    }
    log_message "Unmasking PostgreSQL service..."
    systemctl unmask postgresql | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to unmask PostgreSQL service."
        exit 1
    }
    log_message "Starting PostgreSQL service..."
    timeout -k 10 "$SERVICE_TIMEOUT" systemctl start postgresql | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to start PostgreSQL service."
        exit 1
    }
    log_message "Checking PostgreSQL service status..."
    systemctl status postgresql | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to check PostgreSQL service status."
        exit 1
    }
    log_message "PostgreSQL installed and running."
    log_system_state
}

# Function to install Bacula
install_bacula() {
    log_message "Starting Bacula package installation..."
    timeout -k 10 "$APT_TIMEOUT" env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$BACULA_PACKAGE" | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to install Bacula. Check $LOG_FILE for details."
        exit 1
    }
    # Log the installed Bacula version
    local installed_version=$(dpkg -l | grep bacula | awk '{print $3}' | head -1)
    log_message "Bacula installed successfully. Installed version: $installed_version"
}

# Function to configure Bacula user and directories
configure_bacula() {
    log_message "Configuring Bacula directories..."
    # Create backup and restore directories
    mkdir -p "$BACKUP_DIR" "$RESTORE_DIR" | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to create directories $BACKUP_DIR or $RESTORE_DIR."
        exit 1
    }
    # Set ownership and permissions
    chown -R "$DIR_OWNER:$DIR_GROUP" "$BACKUP_DIR" "$RESTORE_DIR" | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to set ownership for $BACKUP_DIR or $RESTORE_DIR."
        exit 1
    }
    chmod -R 700 "$BACKUP_DIR" "$RESTORE_DIR" | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to set permissions for $BACKUP_DIR or $RESTORE_DIR."
        exit 1
    }
    log_message "Backup and restore directories configured."
}

# Function to configure PostgreSQL for Bacula
configure_postgresql() {
    log_message "Configuring PostgreSQL for Bacula..."
    # Run Bacula database creation scripts
    su - postgres -c "/usr/share/bacula-director/create_postgresql_database" | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to create Bacula database."
        exit 1
    }
    su - postgres -c "/usr/share/bacula-director/make_postgresql_tables" | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to create Bacula tables."
        exit 1
    }
    su - postgres -c "/usr/share/bacula-director/grant_postgresql_privileges" | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to grant PostgreSQL privileges."
        exit 1
    }
    log_message "PostgreSQL configured for Bacula."
}

# Function to restart Bacula services
restart_services() {
    log_message "Restarting Bacula services..."
    for service in "${BACULA_SERVICES[@]}"; do
        timeout -k 10 "$SERVICE_TIMEOUT" systemctl restart "$service" | tee -a "$LOG_FILE" || {
            log_message "ERROR: Failed to restart $service."
            exit 1
        }
        timeout -k 10 "$SERVICE_TIMEOUT" systemctl enable "$service" | tee -a "$LOG_FILE" || {
            log_message "ERROR: Failed to enable $service."
            exit 1
        }
        log_message "$service restarted and enabled."
    done
}

# Function to verify installation
verify_installation() {
    log_message "Verifying Bacula installation..."
    for service in "${BACULA_SERVICES[@]}"; do
        if systemctl is-active --quiet "$service"; then
            log_message "$service is running."
        else
            log_message "ERROR: $service is not running."
            exit 1
        fi
    done
    log_message "Bacula installation verified successfully."
}

# Main execution
echo "Starting Bacula installation script on $(date)" | tee -a "$LOG_FILE"
log_message "Starting Bacula installation script on Ubuntu 24.04..."

check_root
setup_logging
check_requirements
check_existing_install
check_apt_locks
check_postgresql_port
add_postgresql_repo
install_dependencies
install_bacula
configure_bacula
configure_postgresql
restart_services
verify_installation

# Ensure all quotes are closed
log_message "${GREEN}Bacula installation completed successfully!${NC}"
log_message "Log file: $LOG_FILE"
log_message "Next steps:"
log_message "1. Edit configuration files in $CONFIG_DIR to set up backup jobs."
log_message "2. Use 'bconsole' to manage Bacula and test backups."
log_message "3. Check the official Bacula documentation for advanced configuration: https://www.bacula.org"

exit 0