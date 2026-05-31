#!/usr/bin/env bash
# =============================================================================
# IPTables Baseline Firewall — Ubuntu
# Applies a defence-in-depth iptables ruleset suitable for infrastructure
# servers. Allows SSH, ICMP, and all traffic from RFC-1918 private subnets.
# Drops all other inbound traffic. Saves rules persistently via
# iptables-persistent.
#
# Default policy:
#   INPUT   — DROP  (allowlist model)
#   FORWARD — DROP
#   OUTPUT  — ACCEPT
#
# Allowed inbound:
#   - Loopback (lo)
#   - Established / related connections
#   - All traffic from 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
#   - SSH (port auto-detected from sshd_config, default 22)
#   - ICMP from private subnets
#
# Usage:
#   sudo ./setup-iptables.sh
#   sudo ./setup-iptables.sh --ssh-port 2222
#
# Options:
#   --ssh-port <port>   Override SSH port (auto-detected by default)
#
# Author:            Darren Pilkington
# Version:           1.1
# Date:              31-05-2026
# =============================================================================

set -euo pipefail

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/firewall-setup"
LOG_FILE="${LOG_DIR}/setup-iptables-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── Argument parsing ────────────────────────────────────────────────────────
SSH_PORT_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssh-port) SSH_PORT_OVERRIDE="$2"; shift 2 ;;
        --help)
            grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,2\}//'
            exit 0
            ;;
        *) fail "Unknown argument: $1. Use --help for usage." ;;
    esac
done

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]]          || fail "Run as root: sudo ./setup-iptables.sh"
command -v iptables &>/dev/null || fail "iptables not found."

log "Configuring iptables on $(hostname -f 2>/dev/null || hostname)"
log "Log file: ${LOG_FILE}"

# ─── Detect SSH port ─────────────────────────────────────────────────────────
if [[ -n "${SSH_PORT_OVERRIDE}" ]]; then
    SSH_PORT="${SSH_PORT_OVERRIDE}"
else
    SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1)
    SSH_PORT="${SSH_PORT:-22}"
fi
log "SSH port: ${SSH_PORT}"

# ─── Private subnets ─────────────────────────────────────────────────────────
PRIVATE_SUBNETS=("10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16")

# ─── Flush existing rules and reset policies ─────────────────────────────────
log "Flushing existing iptables rules..."
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

log "Setting default chain policies..."
iptables -P INPUT   DROP
iptables -P FORWARD DROP
iptables -P OUTPUT  ACCEPT
log "Default policies: INPUT=DROP, FORWARD=DROP, OUTPUT=ACCEPT"

# ─── Loopback ────────────────────────────────────────────────────────────────
log "Allowing loopback traffic..."
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# ─── Established and related connections ─────────────────────────────────────
log "Allowing established and related inbound connections..."
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# ─── Private subnet access ───────────────────────────────────────────────────
log "Allowing all inbound traffic from private subnets..."
for subnet in "${PRIVATE_SUBNETS[@]}"; do
    iptables -A INPUT -s "${subnet}" -j ACCEPT
    log "  Allowed: ${subnet}"
done

# ─── SSH ─────────────────────────────────────────────────────────────────────
log "Allowing SSH on port ${SSH_PORT}..."
iptables -A INPUT -p tcp --dport "${SSH_PORT}" -j ACCEPT

# ─── ICMP (ping) from private subnets ───────────────────────────────────────
log "Allowing ICMP from private subnets..."
for subnet in "${PRIVATE_SUBNETS[@]}"; do
    iptables -A INPUT -s "${subnet}" -p icmp -j ACCEPT
done

# ─── Install iptables-persistent ─────────────────────────────────────────────
log "Installing iptables-persistent for rule persistence across reboots..."
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent \
    2>&1 | tee -a "${LOG_FILE}"

# ─── Save rules ──────────────────────────────────────────────────────────────
log "Saving iptables rules to /etc/iptables/rules.v4..."
mkdir -p /etc/iptables
iptables-save | tee /etc/iptables/rules.v4 > /dev/null
log "Rules saved."

# ─── Display active rules ────────────────────────────────────────────────────
log "Active iptables rules:"
iptables -L -n -v 2>&1 | tee -a "${LOG_FILE}"

log "Firewall configuration complete. Log: ${LOG_FILE}"
