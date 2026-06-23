#!/usr/bin/env bash
# =============================================================================
# install-certbot-nginx.sh
# =============================================================================
# Installs Certbot and obtains a free Let's Encrypt TLS certificate for Nginx.
#
# What is Let's Encrypt?
# ──────────────────────
# Let's Encrypt is a free, automated certificate authority (CA). It issues
# TLS certificates that browsers trust — the same level of trust as paid
# certificates. Certificates are valid for 90 days and auto-renew.
#
# What is a TLS certificate?
# ──────────────────────────
# TLS (Transport Layer Security) encrypts traffic between a browser and your
# server. Without it:
#   - Traffic is sent in plain text — anyone on the network can read it
#   - Browsers show "Not Secure" warnings
#   - Modern browsers block some features (geolocation, camera, etc.)
#
# Cloud equivalents:
#   AWS   → AWS Certificate Manager (ACM) — free for load balancers
#   Azure → Azure App Service Managed Certificate / Key Vault Certificates
#   GCP   → Google-managed SSL certificates / Certificate Manager
#
# Prerequisites:
#   - Domain name pointing to this server's public IP (A record in DNS)
#   - Ports 80 and 443 open in firewall
#   - Nginx installed and running
#   - Run as root
#
# Usage:
#   sudo ./install-certbot-nginx.sh -d example.com -e admin@example.com
#   sudo ./install-certbot-nginx.sh -d example.com -d www.example.com -e admin@example.com
#
# Options:
#   -d DOMAIN    Domain name (can be repeated for multiple domains/SANs)
#   -e EMAIL     Email for Let's Encrypt expiry notifications
#   -s           Staging mode — test without rate limits (won't be browser-trusted)
#   -h           Show this help
#
# Author  : IT-Architect-UK
# Repo    : https://github.com/IT-Architect-UK/monorepo
# Version : 1.0.0
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
log()     { echo -e "${GREEN}[✔]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✘] ERROR:${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BLUE}${BOLD}━━━ $* ━━━${NC}"; }

# ── Load defaults from .env if present ───────────────────────────────────────
ENV_FILE="$(dirname "$0")/../.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE" && log "Loaded defaults from .env"


[[ $EUID -ne 0 ]] && error "Run as root: sudo $0"

DOMAINS=()
EMAIL="${LE_EMAIL:-}"
STAGING=false

usage() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,1\}//'
    exit 0
}

while getopts "d:e:sh" opt; do
    case $opt in
        d) DOMAINS+=("$OPTARG") ;;
        e) EMAIL="$OPTARG" ;;
        s) STAGING=true ;;
        h) usage ;;
        *) error "Unknown option. Use -h for help." ;;
    esac
done

[[ ${#DOMAINS[@]} -eq 0 ]] && error "Specify at least one domain with -d"
[[ -z "$EMAIL" ]]           && error "Specify an email with -e"

PRIMARY_DOMAIN="${DOMAINS[0]}"

section "Let's Encrypt — Nginx TLS Certificate"
log "Domain(s) : ${DOMAINS[*]}"
log "Email     : $EMAIL"
[[ "$STAGING" == "true" ]] && warn "Staging mode — certificate will NOT be browser-trusted"

section "1 — Verify DNS"
log "Checking DNS resolution for $PRIMARY_DOMAIN..."
RESOLVED_IP=$(dig +short "$PRIMARY_DOMAIN" A | tail -1)
SERVER_IP=$(curl -s --max-time 5 https://api.ipify.org || echo "unknown")
if [[ -z "$RESOLVED_IP" ]]; then
    warn "Could not resolve $PRIMARY_DOMAIN — DNS may not have propagated yet."
    warn "Ensure an A record points $PRIMARY_DOMAIN to this server's IP ($SERVER_IP)"
    read -rp "Continue anyway? [y/N] " continue_anyway
    [[ "${continue_anyway,,}" != "y" ]] && exit 1
else
    log "DNS resolves to: $RESOLVED_IP (this server: $SERVER_IP)"
    [[ "$RESOLVED_IP" != "$SERVER_IP" ]] && warn "IP mismatch — certificate issuance may fail"
fi

section "2 — Install Certbot"
apt-get update -q
apt-get install -y certbot python3-certbot-nginx
log "Certbot installed: $(certbot --version 2>&1)"

section "3 — Obtain Certificate"
DOMAIN_ARGS=()
for d in "${DOMAINS[@]}"; do DOMAIN_ARGS+=(-d "$d"); done
STAGING_FLAG=""; [[ "$STAGING" == "true" ]] && STAGING_FLAG="--staging"

log "Requesting certificate from Let's Encrypt..."
certbot --nginx \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    $STAGING_FLAG \
    "${DOMAIN_ARGS[@]}"

section "4 — Verify Certificate"
CERT_PATH="/etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem"
if [[ -f "$CERT_PATH" ]]; then
    EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_PATH" | cut -d= -f2)
    log "Certificate installed: $CERT_PATH"
    log "Expires: $EXPIRY"
else
    error "Certificate file not found at $CERT_PATH"
fi

section "5 — Verify Auto-Renewal"
# Certbot installs a systemd timer or cron job to renew certificates automatically.
# Certificates are renewed when they have fewer than 30 days remaining.
systemctl is-active --quiet certbot.timer && log "certbot.timer is active (auto-renewal enabled)" \
    || warn "certbot.timer not found — check if a cron job was installed instead"

# Dry-run renewal test
certbot renew --dry-run && log "Renewal dry-run passed"

section "Complete!"
echo ""
log "HTTPS is now active for ${DOMAINS[*]}"
log "Certbot will auto-renew the certificate before it expires"
echo ""
echo "  Test your certificate:"
echo "  https://www.ssllabs.com/ssltest/analyze.html?d=$PRIMARY_DOMAIN"
echo ""
echo "  Certificate location:"
echo "  /etc/letsencrypt/live/$PRIMARY_DOMAIN/"
echo "    ├── fullchain.pem   ← certificate + intermediate chain"
echo "    ├── privkey.pem     ← private key (keep this secret!)"
echo "    └── cert.pem        ← certificate only"
echo ""
