#!/usr/bin/env bash
# =============================================================================
# Install Let's Encrypt TLS Certificate — Ubuntu (Certbot / Snap)
# Installs Certbot via Snap (the current recommended method) and obtains a
# Let's Encrypt certificate for a domain using the Apache or Nginx plugin.
# Certbot auto-renews certificates via a systemd timer.
#
# Prerequisites:
#   - A domain with DNS pointing to this server's public IP
#   - Port 80 and 443 open on the firewall
#   - Apache or Nginx installed and serving the domain
#
# Usage:
#   sudo ./install-tls-certificate.sh --domain example.com --email admin@example.com
#   sudo ./install-tls-certificate.sh --domain example.com --email admin@example.com --webserver nginx
#
# Options:
#   --domain <name>       Domain name to obtain a certificate for (required)
#   --email <address>     Email address for Let's Encrypt notifications (required)
#   --webserver <name>    Web server plugin: apache (default) or nginx
#
# Author:            Darren Pilkington
# Version:           1.1
# Date:              31-05-2026
# =============================================================================

set -euo pipefail

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/tls-certificate"
LOG_FILE="${LOG_DIR}/install-tls-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── Argument parsing ────────────────────────────────────────────────────────
DOMAIN_NAME=""
EMAIL=""
WEBSERVER="apache"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --domain)    DOMAIN_NAME="$2"; shift 2 ;;
        --email)     EMAIL="$2";       shift 2 ;;
        --webserver) WEBSERVER="$2";   shift 2 ;;
        --help)
            grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,2\}//'
            exit 0
            ;;
        *) fail "Unknown argument: $1. Use --help for usage." ;;
    esac
done

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]]       || fail "Run as root: sudo ./install-tls-certificate.sh"
[[ -n "${DOMAIN_NAME}" ]]   || fail "--domain is required."
[[ -n "${EMAIL}" ]]         || fail "--email is required."
[[ "${WEBSERVER}" == "apache" || "${WEBSERVER}" == "nginx" ]] \
    || fail "--webserver must be 'apache' or 'nginx'."

command -v snap &>/dev/null || fail "snapd not found. Install with: apt-get install -y snapd"

log "Installing TLS certificate on $(hostname -f 2>/dev/null || hostname)"
log "  Domain    : ${DOMAIN_NAME}"
log "  Email     : ${EMAIL}"
log "  Webserver : ${WEBSERVER}"
log "Log file: ${LOG_FILE}"

# ─── Update system packages ──────────────────────────────────────────────────
log "Updating package lists..."
apt-get update -y 2>&1 | tee -a "${LOG_FILE}"

# ─── Install Certbot via Snap ────────────────────────────────────────────────
# Snap is the recommended installation method as of Certbot v2.x
log "Ensuring snapd core is up to date..."
snap install core 2>&1 | tee -a "${LOG_FILE}" || true
snap refresh core 2>&1 | tee -a "${LOG_FILE}" || true

log "Installing Certbot via Snap..."
if snap list certbot &>/dev/null 2>&1; then
    log "Certbot already installed via Snap."
else
    snap install --classic certbot 2>&1 | tee -a "${LOG_FILE}"
    ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null || true
    log "Certbot installed."
fi

# ─── Remove legacy Certbot apt package if present ───────────────────────────
if dpkg -l | grep -qE "^ii.*certbot"; then
    log "Removing legacy apt-installed Certbot to avoid conflicts..."
    apt-get remove -y certbot 2>&1 | tee -a "${LOG_FILE}" || true
fi

# ─── Obtain certificate ──────────────────────────────────────────────────────
log "Obtaining Let's Encrypt certificate for ${DOMAIN_NAME}..."
certbot "--${WEBSERVER}" \
    --email "${EMAIL}" \
    --agree-tos \
    --no-eff-email \
    --non-interactive \
    -d "${DOMAIN_NAME}" \
    2>&1 | tee -a "${LOG_FILE}"
log "Certificate obtained successfully."

# ─── Verify auto-renewal ─────────────────────────────────────────────────────
log "Testing Certbot auto-renewal configuration..."
certbot renew --dry-run 2>&1 | tee -a "${LOG_FILE}"
log "Auto-renewal dry-run passed."

log "TLS certificate installation complete."
log "  Certificate: /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem"
log "  Private key: /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem"
log "  Auto-renew : managed by systemd certbot.timer"
log "  Log file   : ${LOG_FILE}"
