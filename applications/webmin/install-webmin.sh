#!/usr/bin/env bash
# =============================================================================
# Webmin Installation — Ubuntu
# Installs Webmin from the official repository using the vendor-provided
# setup script. Configures the apt repository and GPG key, installs the
# package, and verifies the service is running.
#
# Webmin provides a web-based system administration interface accessible
# at https://<server-ip>:10000 after installation.
#
# Usage:
#   sudo ./install-webmin.sh
#
# Author:            Darren Pilkington
# Version:           1.1
# Date:              31-05-2026
# =============================================================================

set -euo pipefail

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/webmin-install"
LOG_FILE="${LOG_DIR}/install-webmin-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || fail "Run as root: sudo ./install-webmin.sh"
command -v apt-get &>/dev/null || fail "apt-get not found — Ubuntu/Debian required."
command -v curl    &>/dev/null || { apt-get install -y curl; }

log "Installing Webmin on $(hostname -f 2>/dev/null || hostname)"
log "Log file: ${LOG_FILE}"

# ─── Clean up any previous failed install artefacts ─────────────────────────
log "Removing any stale Webmin repository and key files..."
rm -f /etc/apt/sources.list.d/webmin.list
rm -f /usr/share/keyrings/webmin-archive-keyring.gpg
rm -f /etc/apt/keyrings/webmin-archive-keyring.gpg
log "Cleanup done."

# ─── Add Webmin repository via official setup script ────────────────────────
SETUP_SCRIPT=$(mktemp /tmp/webmin-setup-XXXXXX.sh)
trap 'rm -f "${SETUP_SCRIPT}"' EXIT

log "Downloading official Webmin repository setup script..."
curl -fsSL https://raw.githubusercontent.com/webmin/webmin/master/webmin-setup-repo.sh \
    -o "${SETUP_SCRIPT}"
log "Setup script downloaded."

log "Running Webmin repository setup (non-interactive)..."
echo "y" | bash "${SETUP_SCRIPT}" 2>&1 | tee -a "${LOG_FILE}"
log "Repository configured."

# ─── Install Webmin ──────────────────────────────────────────────────────────
log "Updating package lists..."
apt-get update -y 2>&1 | tee -a "${LOG_FILE}"

log "Installing Webmin..."
DEBIAN_FRONTEND=noninteractive apt-get install -y webmin --install-recommends \
    2>&1 | tee -a "${LOG_FILE}"
log "Webmin installed."

# ─── Enable and start service ────────────────────────────────────────────────
log "Enabling Webmin service..."
systemctl enable webmin
systemctl restart webmin

# ─── Verify ──────────────────────────────────────────────────────────────────
log "Verifying Webmin service status..."
if systemctl is-active --quiet webmin; then
    log "Webmin is running."
else
    fail "Webmin service is not running. Check: journalctl -u webmin"
fi

SERVER_IP=$(hostname -I | awk '{print $1}')
WEBMIN_VERSION=$(dpkg -l webmin 2>/dev/null | awk '/^ii/ {print $3}' || echo "unknown")

log "Webmin installation complete."
log "  Version   : ${WEBMIN_VERSION}"
log "  URL       : https://${SERVER_IP}:10000"
log "  Login     : root (or any sudo user) with their system password"
log "  Log file  : ${LOG_FILE}"
