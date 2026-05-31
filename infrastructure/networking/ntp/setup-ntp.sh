#!/usr/bin/env bash
# =============================================================================
# Configure NTP — Ubuntu (systemd-timesyncd)
# Configures systemd-timesyncd to use a specified NTP server. By default,
# detects the default gateway and uses it as the NTP source (common in
# corporate environments where the gateway or firewall provides NTP).
#
# Backs up the existing timesyncd.conf before making changes.
# Updates are idempotent — safe to re-run.
#
# Usage:
#   sudo ./setup-ntp.sh
#   sudo ./setup-ntp.sh --ntp-server 192.168.1.1
#   sudo ./setup-ntp.sh --ntp-server pool.ntp.org --fallback-server time.cloudflare.com
#
# Options:
#   --ntp-server <ip/host>        Primary NTP server (default: gateway IP)
#   --fallback-server <ip/host>   Fallback NTP server (optional)
#
# Author:            Darren Pilkington
# Version:           1.1
# Date:              31-05-2026
# =============================================================================

set -euo pipefail

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/network-configuration"
LOG_FILE="${LOG_DIR}/setup-ntp-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── Argument parsing ────────────────────────────────────────────────────────
NTP_SERVER=""
FALLBACK_SERVER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ntp-server)      NTP_SERVER="$2";      shift 2 ;;
        --fallback-server) FALLBACK_SERVER="$2"; shift 2 ;;
        --help)
            grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,2\}//'
            exit 0
            ;;
        *) fail "Unknown argument: $1. Use --help for usage." ;;
    esac
done

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || fail "Run as root: sudo ./setup-ntp.sh"
command -v timedatectl &>/dev/null || fail "timedatectl not found — systemd required."

log "Configuring NTP on $(hostname -f 2>/dev/null || hostname)"
log "Log file: ${LOG_FILE}"

# ─── Detect NTP server if not specified ──────────────────────────────────────
if [[ -z "${NTP_SERVER}" ]]; then
    log "No --ntp-server specified — detecting default gateway..."
    NTP_SERVER=$(ip route show default 2>/dev/null | awk '/default/ {print $3}' | head -1)
    [[ -n "${NTP_SERVER}" ]] || fail "Could not detect default gateway. Use --ntp-server to specify one."
    log "Using default gateway as NTP server: ${NTP_SERVER}"
fi

log "NTP server: ${NTP_SERVER}"
[[ -n "${FALLBACK_SERVER}" ]] && log "Fallback NTP server: ${FALLBACK_SERVER}"

# ─── Back up existing configuration ─────────────────────────────────────────
TIMESYNCD_CONF="/etc/systemd/timesyncd.conf"
BACKUP_FILE="${TIMESYNCD_CONF}.bak.$(date '+%Y%m%d-%H%M%S')"

if [[ -f "${TIMESYNCD_CONF}" ]]; then
    cp "${TIMESYNCD_CONF}" "${BACKUP_FILE}"
    log "Backed up ${TIMESYNCD_CONF} to ${BACKUP_FILE}"
fi

# ─── Update timesyncd.conf ────────────────────────────────────────────────────
log "Updating ${TIMESYNCD_CONF}..."

# Update or add NTP= line
if grep -q "^NTP=" "${TIMESYNCD_CONF}" 2>/dev/null; then
    sed -i "s|^NTP=.*|NTP=${NTP_SERVER}|" "${TIMESYNCD_CONF}"
elif grep -q "^#NTP=" "${TIMESYNCD_CONF}" 2>/dev/null; then
    sed -i "s|^#NTP=.*|NTP=${NTP_SERVER}|" "${TIMESYNCD_CONF}"
else
    echo "NTP=${NTP_SERVER}" >> "${TIMESYNCD_CONF}"
fi

# Update or add FallbackNTP= line if provided
if [[ -n "${FALLBACK_SERVER}" ]]; then
    if grep -q "^FallbackNTP=" "${TIMESYNCD_CONF}" 2>/dev/null; then
        sed -i "s|^FallbackNTP=.*|FallbackNTP=${FALLBACK_SERVER}|" "${TIMESYNCD_CONF}"
    elif grep -q "^#FallbackNTP=" "${TIMESYNCD_CONF}" 2>/dev/null; then
        sed -i "s|^#FallbackNTP=.*|FallbackNTP=${FALLBACK_SERVER}|" "${TIMESYNCD_CONF}"
    else
        echo "FallbackNTP=${FALLBACK_SERVER}" >> "${TIMESYNCD_CONF}"
    fi
fi

log "timesyncd.conf updated:"
grep -E "^(NTP|FallbackNTP)=" "${TIMESYNCD_CONF}" | tee -a "${LOG_FILE}" || true

# ─── Restart timesyncd ────────────────────────────────────────────────────────
log "Restarting systemd-timesyncd..."
systemctl restart systemd-timesyncd
log "systemd-timesyncd restarted."

# ─── Verify synchronisation ───────────────────────────────────────────────────
log "Waiting up to 30 seconds for NTP synchronisation..."
SYNCED=false
for i in $(seq 1 6); do
    SYNC_STATUS=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo "unknown")
    if [[ "${SYNC_STATUS}" == "yes" ]]; then
        SYNCED=true
        break
    fi
    sleep 5
done

if [[ "${SYNCED}" == true ]]; then
    log "NTP synchronisation confirmed."
else
    warn "NTP synchronisation not yet active. This is normal immediately after configuration — check with: timedatectl status"
fi

log "NTP configuration complete."
timedatectl status 2>&1 | tee -a "${LOG_FILE}"
log "Log: ${LOG_FILE}"
