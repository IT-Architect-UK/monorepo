#!/usr/bin/env bash
# =============================================================================
# setup-auto-renewal.sh
# =============================================================================
# Ensures Certbot auto-renewal is properly configured and verified.
# Run this if you installed a certificate manually or want to check renewal.
#
# What it does:
#   1. Checks if a systemd timer or cron job exists for renewal
#   2. Creates a systemd timer if neither exists
#   3. Runs a dry-run renewal test to confirm everything works
#   4. Lists all installed certificates and their expiry dates
#
# Usage:
#   sudo ./setup-auto-renewal.sh
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

[[ $EUID -ne 0 ]] && error "Run as root: sudo $0"
command -v certbot &>/dev/null || error "Certbot not installed. Run install-certbot-nginx.sh or install-certbot-apache.sh first."

section "Certbot Auto-Renewal Setup"

section "1 — Check Existing Renewal Configuration"

TIMER_ACTIVE=false
CRON_ACTIVE=false

if systemctl list-timers certbot.timer &>/dev/null && systemctl is-active --quiet certbot.timer; then
    log "systemd timer 'certbot.timer' is active"
    systemctl status certbot.timer --no-pager
    TIMER_ACTIVE=true
fi

if crontab -l 2>/dev/null | grep -q certbot; then
    log "Cron job for Certbot found"
    crontab -l | grep certbot
    CRON_ACTIVE=true
fi

if [[ "$TIMER_ACTIVE" == "false" && "$CRON_ACTIVE" == "false" ]]; then
    warn "No automatic renewal configured. Setting up systemd timer..."

    # Some Certbot versions install the timer automatically; try enabling it first
    if systemctl enable --now certbot.timer 2>/dev/null; then
        log "certbot.timer enabled via systemctl"
    else
        # Fallback: create a custom systemd timer
        warn "Creating custom renewal timer..."
        cat > /etc/systemd/system/certbot-renewal.service << 'SERVICE'
[Unit]
Description=Certbot Certificate Renewal
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/bin/certbot renew --quiet --deploy-hook "systemctl reload nginx 2>/dev/null || systemctl reload apache2 2>/dev/null || true"
StandardOutput=journal
StandardError=journal
SERVICE

        cat > /etc/systemd/system/certbot-renewal.timer << 'TIMER'
[Unit]
Description=Run Certbot renewal twice daily

[Timer]
# Run at 00:30 and 12:30 — Let's Encrypt recommends running twice daily
OnCalendar=*-*-* 00,12:30:00
RandomizedDelaySec=3600   # Spread load on Let's Encrypt servers
Persistent=true

[Install]
WantedBy=timers.target
TIMER

        systemctl daemon-reload
        systemctl enable --now certbot-renewal.timer
        log "Custom certbot-renewal.timer created and enabled"
    fi
fi

section "2 — Test Renewal (Dry Run)"
log "Running renewal dry-run..."
certbot renew --dry-run && log "Dry-run passed — renewal will work when certificates are due"

section "3 — Current Certificates"
echo ""
certbot certificates
echo ""

section "Summary"
log "Auto-renewal is configured. Certificates renew automatically 30 days before expiry."
warn "Ensure ports 80/443 remain accessible for renewal (HTTP-01 challenge)"
echo ""
echo "  Manual renewal command (if needed):"
echo "  certbot renew"
echo ""
echo "  Force renewal of a specific certificate:"
echo "  certbot renew --cert-name example.com --force-renewal"
