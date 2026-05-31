#!/usr/bin/env bash
# =============================================================================
# Disable IPv6 — Ubuntu
# Persistently disables IPv6 across all network interfaces by writing
# sysctl parameters. Checks for existing entries before writing to prevent
# duplicate lines on repeated runs (idempotent).
#
# Changes made:
#   /etc/sysctl.conf — net.ipv6.conf.*.disable_ipv6 = 1
#
# Applied immediately via: sysctl -p
#
# Usage:
#   sudo ./disable-ipv6.sh
#
# Author:            Darren Pilkington
# Version:           1.1
# Date:              31-05-2026
# =============================================================================

set -euo pipefail

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/system-configuration"
LOG_FILE="${LOG_DIR}/disable-ipv6-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || fail "Run as root: sudo ./disable-ipv6.sh"

log "Disabling IPv6 on $(hostname -f 2>/dev/null || hostname)"
log "Log file: ${LOG_FILE}"

# ─── Write sysctl parameters (idempotent) ────────────────────────────────────
log "Writing IPv6 disable parameters to /etc/sysctl.conf..."

declare -A IPV6_PARAMS=(
    ["net.ipv6.conf.all.disable_ipv6"]="1"
    ["net.ipv6.conf.default.disable_ipv6"]="1"
    ["net.ipv6.conf.lo.disable_ipv6"]="1"
)

for param in "${!IPV6_PARAMS[@]}"; do
    value="${IPV6_PARAMS[$param]}"
    if grep -qE "^${param}\s*=" /etc/sysctl.conf 2>/dev/null; then
        # Update existing entry to ensure correct value
        sed -i "s|^${param}\s*=.*|${param}=${value}|" /etc/sysctl.conf
        log "Updated existing entry: ${param}=${value}"
    else
        echo "${param}=${value}" >> /etc/sysctl.conf
        log "Added new entry: ${param}=${value}"
    fi
done

# ─── Apply changes immediately ───────────────────────────────────────────────
log "Applying sysctl configuration..."
sysctl -p 2>&1 | tee -a "${LOG_FILE}"
log "Sysctl configuration applied."

# ─── Verify ──────────────────────────────────────────────────────────────────
log "Verifying IPv6 is disabled..."
IPV6_STATUS=$(cat /proc/sys/net/ipv6/conf/all/disable_ipv6 2>/dev/null || echo "unknown")
if [[ "${IPV6_STATUS}" == "1" ]]; then
    log "IPv6 successfully disabled (disable_ipv6=1)."
else
    warn "IPv6 may not be fully disabled (disable_ipv6=${IPV6_STATUS}). A reboot may be required."
fi

log "IPv6 disable complete. Log: ${LOG_FILE}"
