#!/usr/bin/env bash
# =============================================================================
# Ubuntu Server Baseline Configuration
# Orchestrates a standard set of configuration scripts to harden and prepare
# a fresh Ubuntu server. Resolves the scripts directory relative to this file
# so it runs correctly regardless of where the repo is cloned.
#
# Scripts executed (in order):
#   1. apply-branding.sh          — MOTD and shell prompt
#   2. disable-cloud-init.sh      — Prevent cloud-init re-runs
#   3. disable-ipv6.sh            — Disable IPv6 system-wide
#   4. dns-default-gateway.sh     — Set static DNS and gateway
#   5. setup-iptables.sh          — Apply iptables baseline ruleset
#   6. extend-disks.sh            — LVM disk extension
#
# Usage:
#   sudo ./server-baseline.sh
#
# Notes:
#   Version:           1.1
#   Author:            Darren Pilkington
#   Modification Date: 31-05-2026
# =============================================================================

set -euo pipefail

# ─── Resolve paths relative to this script ───────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_BASE="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/server-baseline"
LOG_FILE="${LOG_DIR}/server-baseline-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── Pre-flight checks ───────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || fail "This script must be run as root (sudo)."

log "Server baseline starting on $(hostname -f 2>/dev/null || hostname)"
log "Log file: ${LOG_FILE}"

# ─── Run baseline scripts ────────────────────────────────────────────────────
SCRIPTS_TO_RUN=(
    "configuration/apply-branding.sh"
    "configuration/disable-cloud-init.sh"
    "configuration/disable-ipv6.sh"
    "configuration/dns-default-gateway.sh"
    "configuration/setup-iptables.sh"
    "configuration/extend-disks.sh"
)

for script in "${SCRIPTS_TO_RUN[@]}"; do
    script_path="${SCRIPTS_BASE}/${script}"
    if [[ ! -f "${script_path}" ]]; then
        log "WARNING: ${script_path} not found — skipping."
        continue
    fi
    chmod +x "${script_path}"
    log "Running: ${script}"
    bash "${script_path}" || fail "${script} failed."
    log "Completed: ${script}"
done

log "All baseline scripts executed successfully."

# ─── System update ───────────────────────────────────────────────────────────
log "Running full system upgrade..."
DEBIAN_FRONTEND=noninteractive apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
DEBIAN_FRONTEND=noninteractive apt-get autoclean -y
log "System upgrade complete."

# ─── Reboot ──────────────────────────────────────────────────────────────────
log "Baseline complete. Rebooting in 5 seconds..."
sleep 5
reboot
