#!/usr/bin/env bash
# =============================================================================
# install-certbot-apache.sh
# =============================================================================
# Installs Certbot and obtains a Let's Encrypt TLS certificate for Apache.
# Identical workflow to install-certbot-nginx.sh but uses the Apache plugin.
#
# Usage:
#   sudo ./install-certbot-apache.sh -d example.com -e admin@example.com
#
# Options:
#   -d DOMAIN    Domain name (can be repeated)
#   -e EMAIL     Email for expiry notifications
#   -s           Staging mode (test without rate limits)
#   -h           Help
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

DOMAINS=(); EMAIL=""; STAGING=false

while getopts "d:e:sh" opt; do
    case $opt in
        d) DOMAINS+=("$OPTARG") ;;
        e) EMAIL="$OPTARG" ;;
        s) STAGING=true ;;
        h) sed -n '/^# =/,/^# =/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) error "Unknown option. Use -h for help." ;;
    esac
done

[[ ${#DOMAINS[@]} -eq 0 ]] && error "Specify at least one domain with -d"
[[ -z "$EMAIL" ]]           && error "Specify an email with -e"

PRIMARY_DOMAIN="${DOMAINS[0]}"

section "Let's Encrypt — Apache TLS Certificate"
log "Domain(s) : ${DOMAINS[*]}"

section "1 — Install Certbot"
apt-get update -q
# Enable Apache SSL module if not already active
a2enmod ssl 2>/dev/null || true
apt-get install -y certbot python3-certbot-apache
log "Certbot $(certbot --version 2>&1) ready"

section "2 — Obtain Certificate"
DOMAIN_ARGS=()
for d in "${DOMAINS[@]}"; do DOMAIN_ARGS+=(-d "$d"); done
STAGING_FLAG=""; [[ "$STAGING" == "true" ]] && STAGING_FLAG="--staging"

certbot --apache \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    $STAGING_FLAG \
    "${DOMAIN_ARGS[@]}"

section "3 — Verify"
certbot renew --dry-run && log "Auto-renewal dry-run passed"

EXPIRY=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$PRIMARY_DOMAIN/fullchain.pem" | cut -d= -f2)
log "Certificate valid until: $EXPIRY"

section "Complete!"
log "HTTPS enabled for ${DOMAINS[*]}"
echo "  Test: https://www.ssllabs.com/ssltest/analyze.html?d=$PRIMARY_DOMAIN"
