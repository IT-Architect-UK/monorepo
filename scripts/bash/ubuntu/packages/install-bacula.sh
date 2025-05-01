#!/bin/bash

# Simplified script to install Bacula interactively and optionally install Bacularis web interface on Ubuntu 24.04

# Variables
LOG_FILE="/var/log/bacula_install_$(date +%Y%m%d_%H%M%S).log"
BACKUP_DIR="/bacula/backup"
RESTORE_DIR="/bacula/restore"
CONFIG_DIR="/etc/bacula"
BACULA_PACKAGE="bacula"
Bacularis_PACKAGES=("baculum-common" "baculum-api" "baculum-web")
BACULA_SERVICES=("bacula-dir" "bacula-sd" "bacula-fd")
MIN_RAM="2G"  # Minimum RAM recommended for Bacula server
VERBOSE=true  # Enable verbose logging
APT_TIMEOUT=900  # Timeout for apt-get install in seconds (15 minutes)
SERVICE_TIMEOUT=30  # Timeout for service commands in seconds
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

# Function to install Bacula interactively
install_bacula() {
    log_message "Starting Bacula installation interactively..."
    log_message "Please respond to the prompts for database configuration and other settings."
    # Run apt-get install without tee or timeout to ensure TTY for debconf prompts
    stdbuf -oL apt-get install "$BACULA_PACKAGE" >> "$LOG_FILE" 2>&1 || {
        log_message "ERROR: Failed to install Bacula. Check $LOG_FILE for details."
        exit 1
    }
    # Log the installed Bacula version
    local installed_version=$(dpkg -l | grep bacula | awk '{print $3}' | head -1)
    log_message "Bacula installed successfully. Installed version: $installed_version"
}

# Function to configure Bacula directories
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

# Function to install Bacularis
install_bacularis() {
    log_message "Installing Bacularis web interface..."
    # Install Apache and PHP prerequisites
    timeout -k 10 "$APT_TIMEOUT" env DEBIAN_FRONTEND=noninteractive apt-get install -y apache2 php php-pgsql php-json php-curl | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to install Apache and PHP."
        exit 1
    }
    # Add Bacularis repository
    wget -qO - http://bacula.org/downloads/baculum/baculum.pub | apt-key add - | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to add Bacularis repository key."
        exit 1
    }
    echo "deb http://bacula.org/downloads/baculum/stable-24.04/ubuntu noble main" > /etc/apt/sources.list.d/baculum.list
    apt-get update -y | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to update package lists after adding Bacularis repository."
        exit 1
    }
    # Install Bacularis packages
    timeout -k 10 "$APT_TIMEOUT" env DEBIAN_FRONTEND=noninteractive apt-get install -y "${Bacularis_PACKAGES[@]}" | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to install Bacularis."
        exit 1
    }
    # Configure Bacularis
    log_message "Configuring Bacularis..."
    read -p "Enter the PostgreSQL user for Bacularis (default: bacula): " pg_user
    pg_user=${pg_user:-bacula}
    read -p "Enter the PostgreSQL password for Bacularis: " pg_password
    cat << EOF > /etc/baculum/Config-api-apache/baculum.api.conf
[db]
type = pgsql
host = localhost
name = bacula
user = $pg_user
password = $pg_password
EOF
    cat << EOF > /etc/baculum/Config-web-apache/baculum.web.conf
[db]
type = pgsql
host = localhost
name = bacula
user = $pg_user
password = $pg_password
EOF
    chown www-data:www-data /etc/baculum/Config-*-apache/*.conf
    chmod 640 /etc/baculum/Config-*-apache/*.conf
    systemctl restart apache2 | tee -a "$LOG_FILE" || {
        log_message "ERROR: Failed to restart Apache."
        exit 1
    }
    log_message "Bacularis installed and configured. Access at http://<server-ip>/baculum"
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
install_bacula
configure_bacula
restart_services
verify_installation

# Prompt for Bacularis installation
log_message "Bacula base installation completed."
read -p "Do you want to install the Bacularis web management interface? (y/N): " install_bacularis
if [[ "$install_bacularis" =~ ^[Yy]$ ]]; then
    install_bacularis
else
    log_message "Skipping Bacularis installation as per user choice."
fi

# Final output
log_message "${GREEN}Bacula installation completed successfully!${NC}"
log_message "Log file: $LOG_FILE"
if [[ "$install_bacularis" =~ ^[Yy]$ ]]; then
    log_message "Bacularis web interface available at http://<server-ip>/baculum"
fi
log_message "Next steps:"
if [[ "$install_bacularis" =~ ^[Yy]$ ]]; then
    log_message "1. Access Bacularis to manage Bacula: http://<server-ip>/baculum"
fi
log_message "2. Edit configuration files in $CONFIG_DIR for advanced setup."
log_message "3. Use 'bconsole' for command-line management."
log_message "4. Check the official Bacula documentation: https://www.bacula.org"

exit 0