#!/usr/bin/env bash
# =============================================================================
# Bacula Backup Server Installation — Ubuntu
# Installs Bacula (Director, Storage Daemon, File Daemon) on Ubuntu 24.04.
# Optionally installs the Bacularis web management interface.
#
# Bacula requires interactive debconf prompts during installation for
# database configuration. This script uses the `script` utility to
# provide a proper TTY for those prompts.
#
# Usage:
#   sudo ./install-bacula.sh
#   sudo ./install-bacula.sh --skip-bacularis
#
# Options:
#   --skip-bacularis    Skip the optional Bacularis web interface installation
#
# Author:            Darren Pilkington
# Version:           1.1
# Date:              31-05-2026
# =============================================================================

set -euo pipefail

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/bacula-install"
LOG_FILE="${LOG_DIR}/install-bacula-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── Argument parsing ────────────────────────────────────────────────────────
SKIP_BACULARIS=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-bacularis) SKIP_BACULARIS=true; shift ;;
        --help)
            grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,2\}//'
            exit 0
            ;;
        *) fail "Unknown argument: $1. Use --help for usage." ;;
    esac
done

# ─── Configuration ───────────────────────────────────────────────────────────
BACKUP_DIR="/bacula/backup"
RESTORE_DIR="/bacula/restore"
BACULA_SERVICES=("bacula-dir" "bacula-sd" "bacula-fd")
SERVICE_TIMEOUT=30
BACULARIS_PACKAGES=("baculum-common" "baculum-api" "baculum-web")

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || fail "Run as root: sudo ./install-bacula.sh"
command -v apt-get &>/dev/null || fail "apt-get not found — Ubuntu/Debian required."

log "Installing Bacula on $(hostname -f 2>/dev/null || hostname)"
log "Log file: ${LOG_FILE}"

# ─── System requirements check ───────────────────────────────────────────────
log "Checking system requirements..."
TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
FREE_DISK=$(df -m / | tail -1 | awk '{print $4}')

[[ "${TOTAL_RAM}" -ge 2048 ]] \
    || warn "System has ${TOTAL_RAM} MB RAM. Bacula recommends at least 2 GB."
[[ "${FREE_DISK}" -ge 2048 ]] \
    || warn "Only ${FREE_DISK} MB free on /. Bacula installation may fail."

log "RAM: ${TOTAL_RAM} MB | Free disk: ${FREE_DISK} MB"

# ─── Check for existing Bacula installation ──────────────────────────────────
log "Checking for existing Bacula installation..."
if dpkg -l bacula 2>/dev/null | grep -q "^ii"; then
    warn "Bacula is already installed."
    read -r -p "Continue anyway? This may overwrite configuration files. [y/N] " CONFIRM
    [[ "${CONFIRM,,}" == "y" ]] || { log "Aborted by user."; exit 0; }
fi

# ─── Check apt locks ─────────────────────────────────────────────────────────
log "Checking for apt lock conflicts..."
if fuser /var/lib/dpkg/lock-frontend &>/dev/null 2>&1; then
    fail "Another apt process is running. Wait for it to complete before retrying."
fi

# ─── Update package lists ────────────────────────────────────────────────────
log "Updating package lists..."
apt-get update -y 2>&1 | tee -a "${LOG_FILE}"

# ─── Install Bacula (requires interactive TTY for debconf) ───────────────────
log "Installing Bacula (interactive — answer database configuration prompts)..."
TEMP_LOG=$(mktemp)
trap 'rm -f "${TEMP_LOG}"' EXIT

script -q -c "apt-get install -y bacula" "${TEMP_LOG}" 2>&1 \
    || { cat "${TEMP_LOG}" >> "${LOG_FILE}"; fail "Bacula installation failed."; }
cat "${TEMP_LOG}" >> "${LOG_FILE}"

INSTALLED_VERSION=$(dpkg -l bacula 2>/dev/null | awk '/^ii/ {print $3}' || echo "unknown")
log "Bacula ${INSTALLED_VERSION} installed."

# ─── Create backup and restore directories ───────────────────────────────────
log "Creating backup and restore directories..."
mkdir -p "${BACKUP_DIR}" "${RESTORE_DIR}"
chown -R root:root "${BACKUP_DIR}" "${RESTORE_DIR}"
chmod -R 700 "${BACKUP_DIR}" "${RESTORE_DIR}"
log "Directories created: ${BACKUP_DIR}, ${RESTORE_DIR}"

# ─── Start and enable Bacula services ────────────────────────────────────────
log "Starting and enabling Bacula services..."
for service in "${BACULA_SERVICES[@]}"; do
    timeout "${SERVICE_TIMEOUT}" systemctl restart "${service}" 2>&1 | tee -a "${LOG_FILE}" \
        || fail "Failed to restart ${service}."
    systemctl enable "${service}"
    log "  ${service}: started and enabled."
done

# ─── Verify services ─────────────────────────────────────────────────────────
log "Verifying Bacula services..."
for service in "${BACULA_SERVICES[@]}"; do
    if systemctl is-active --quiet "${service}"; then
        log "  ${service}: running."
    else
        fail "${service} is not running after install. Check: journalctl -u ${service}"
    fi
done

# ─── Optional: Bacularis web interface ───────────────────────────────────────
if [[ "${SKIP_BACULARIS}" == false ]]; then
    read -r -p "Install Bacularis web management interface? [y/N] " INSTALL_WEB
    if [[ "${INSTALL_WEB,,}" == "y" ]]; then
        log "Installing Bacularis web interface..."

        # Check Apache port availability
        if ss -tlnp 2>/dev/null | grep -q ":80 "; then
            fail "Port 80 is in use. Stop the conflicting service before installing Bacularis."
        fi

        # Install Apache and PHP prerequisites
        log "Installing Apache and PHP prerequisites..."
        TEMP_LOG2=$(mktemp)
        script -q -c "apt-get install -y apache2 php php-pgsql php-json php-curl" "${TEMP_LOG2}" 2>&1 \
            || { cat "${TEMP_LOG2}" >> "${LOG_FILE}"; fail "Apache/PHP installation failed."; }
        cat "${TEMP_LOG2}" >> "${LOG_FILE}"
        rm -f "${TEMP_LOG2}"

        # Add Bacularis repository using modern keyring method
        log "Adding Bacularis apt repository..."
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL http://bacula.org/downloads/baculum/baculum.pub \
            | gpg --dearmor -o /etc/apt/keyrings/baculum-archive-keyring.gpg
        echo "deb [signed-by=/etc/apt/keyrings/baculum-archive-keyring.gpg] http://bacula.org/downloads/baculum/stable-24.04/ubuntu noble main" \
            > /etc/apt/sources.list.d/baculum.list
        apt-get update -y 2>&1 | tee -a "${LOG_FILE}"

        # Install Bacularis packages
        log "Installing Bacularis packages..."
        TEMP_LOG3=$(mktemp)
        script -q -c "apt-get install -y ${BACULARIS_PACKAGES[*]}" "${TEMP_LOG3}" 2>&1 \
            || { cat "${TEMP_LOG3}" >> "${LOG_FILE}"; fail "Bacularis installation failed."; }
        cat "${TEMP_LOG3}" >> "${LOG_FILE}"
        rm -f "${TEMP_LOG3}"

        # Configure Bacularis database connection
        read -r -p "PostgreSQL user for Bacularis [bacula]: " PG_USER
        PG_USER="${PG_USER:-bacula}"
        read -r -s -p "PostgreSQL password: " PG_PASSWORD
        echo ""

        for conf_dir in Config-api-apache Config-web-apache; do
            conf_file="/etc/baculum/${conf_dir}/baculum.$(echo "${conf_dir}" | cut -d- -f2).conf"
            cat > "${conf_file}" <<EOF
[db]
type = pgsql
host = localhost
name = bacula
user = ${PG_USER}
password = ${PG_PASSWORD}
EOF
            chown www-data:www-data "${conf_file}"
            chmod 640 "${conf_file}"
        done

        systemctl restart apache2 2>&1 | tee -a "${LOG_FILE}"
        log "Bacularis installed."

        SERVER_IP=$(hostname -I | awk '{print $1}')
        log "  Bacularis URL: http://${SERVER_IP}/baculum"
    else
        log "Skipping Bacularis installation."
    fi
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
log "Bacula installation complete."
log "  Version      : ${INSTALLED_VERSION}"
log "  Backup dir   : ${BACKUP_DIR}"
log "  Restore dir  : ${RESTORE_DIR}"
log "  Management   : bconsole (CLI)"
log "  Config dir   : /etc/bacula"
log "  Log file     : ${LOG_FILE}"
log ""
log "Next steps:"
log "  1. Edit /etc/bacula/bacula-dir.conf to configure jobs and clients."
log "  2. Run 'bconsole' to manage Bacula interactively."
log "  3. Reference: https://www.bacula.org/documentation/"
