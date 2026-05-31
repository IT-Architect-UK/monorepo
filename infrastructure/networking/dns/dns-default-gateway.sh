#!/usr/bin/env bash
# =============================================================================
# Configure DNS — Ubuntu (systemd-resolved)
# Sets the DNS server for all active network interfaces using resolvectl,
# which is the correct method on modern Ubuntu (22.04+) with systemd-resolved.
# Optionally sets the DNS search domain.
#
# By default, derives the DNS server IP from the default gateway (assumes the
# gateway acts as a local DNS resolver — common in home labs and corporate LANs).
# Override with --dns-server to specify any IP.
#
# Usage:
#   sudo ./dns-default-gateway.sh
#   sudo ./dns-default-gateway.sh --dns-server 8.8.8.8 --dns-server 8.8.4.4
#   sudo ./dns-default-gateway.sh --dns-server 192.168.1.1 --search-domain corp.local
#
# Options:
#   --dns-server <ip>       DNS server IP (repeatable; default: gateway IP)
#   --search-domain <name>  DNS search domain to append (optional)
#
# Author:            Darren Pilkington
# Version:           1.1
# Date:              31-05-2026
# =============================================================================

set -euo pipefail

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/network-configuration"
LOG_FILE="${LOG_DIR}/dns-configure-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── Argument parsing ────────────────────────────────────────────────────────
DNS_SERVERS=()
SEARCH_DOMAIN=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dns-server)    DNS_SERVERS+=("$2"); shift 2 ;;
        --search-domain) SEARCH_DOMAIN="$2"; shift 2 ;;
        --help)
            grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,2\}//'
            exit 0
            ;;
        *) fail "Unknown argument: $1. Use --help for usage." ;;
    esac
done

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || fail "Run as root: sudo ./dns-default-gateway.sh"
command -v resolvectl &>/dev/null || fail "resolvectl not found — Ubuntu 20.04+ with systemd-resolved required."

log "Configuring DNS on $(hostname -f 2>/dev/null || hostname)"
log "Log file: ${LOG_FILE}"

# ─── Resolve default DNS if not provided ─────────────────────────────────────
if [[ ${#DNS_SERVERS[@]} -eq 0 ]]; then
    log "No --dns-server specified — detecting default gateway..."
    GATEWAY=$(ip route show default 2>/dev/null | awk '/default/ {print $3}' | head -1)
    [[ -n "${GATEWAY}" ]] || fail "Could not detect default gateway. Specify --dns-server explicitly."
    DNS_SERVERS=("${GATEWAY}")
    log "Using default gateway as DNS server: ${GATEWAY}"
fi

log "DNS servers to configure: ${DNS_SERVERS[*]}"
[[ -n "${SEARCH_DOMAIN}" ]] && log "Search domain: ${SEARCH_DOMAIN}"

# ─── Apply DNS to all active interfaces ──────────────────────────────────────
log "Detecting active network interfaces..."
INTERFACES=()
while IFS= read -r iface; do
    [[ "${iface}" == "lo" ]] && continue
    INTERFACES+=("${iface}")
done < <(ip -o link show up | awk -F': ' '{print $2}' | cut -d'@' -f1)

[[ ${#INTERFACES[@]} -gt 0 ]] || fail "No active non-loopback interfaces found."

for iface in "${INTERFACES[@]}"; do
    log "Applying DNS to interface: ${iface}..."
    resolvectl dns "${iface}" "${DNS_SERVERS[@]}"
    [[ -n "${SEARCH_DOMAIN}" ]] && resolvectl domain "${iface}" "${SEARCH_DOMAIN}"
    log "  DNS applied to ${iface}: ${DNS_SERVERS[*]}"
done

# ─── Make resolution persistent via resolved.conf ────────────────────────────
# resolvectl settings are runtime-only by default; persist them in resolved.conf
log "Persisting DNS settings in /etc/systemd/resolved.conf..."
RESOLVED_CONF="/etc/systemd/resolved.conf"
DNS_LINE="DNS=${DNS_SERVERS[*]}"

if grep -q "^DNS=" "${RESOLVED_CONF}" 2>/dev/null; then
    sed -i "s|^DNS=.*|${DNS_LINE}|" "${RESOLVED_CONF}"
elif grep -q "^#DNS=" "${RESOLVED_CONF}" 2>/dev/null; then
    sed -i "s|^#DNS=.*|${DNS_LINE}|" "${RESOLVED_CONF}"
else
    echo "${DNS_LINE}" >> "${RESOLVED_CONF}"
fi

if [[ -n "${SEARCH_DOMAIN}" ]]; then
    DOMAINS_LINE="Domains=${SEARCH_DOMAIN}"
    if grep -q "^Domains=" "${RESOLVED_CONF}" 2>/dev/null; then
        sed -i "s|^Domains=.*|${DOMAINS_LINE}|" "${RESOLVED_CONF}"
    elif grep -q "^#Domains=" "${RESOLVED_CONF}" 2>/dev/null; then
        sed -i "s|^#Domains=.*|${DOMAINS_LINE}|" "${RESOLVED_CONF}"
    else
        echo "${DOMAINS_LINE}" >> "${RESOLVED_CONF}"
    fi
fi

log "resolved.conf updated."

# ─── Restart resolved and verify ─────────────────────────────────────────────
log "Restarting systemd-resolved..."
systemctl restart systemd-resolved
log "systemd-resolved restarted."

log "DNS resolution status:"
resolvectl status 2>&1 | tee -a "${LOG_FILE}"

log "DNS configuration complete. Log: ${LOG_FILE}"
