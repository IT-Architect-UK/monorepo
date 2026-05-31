#!/usr/bin/env bash
# =============================================================================
# Disable Cloud-Init — Ubuntu
# Prevents cloud-init from running on subsequent boots. Used on VM templates
# and servers that have completed initial provisioning and should not have
# their configuration overwritten by cloud metadata.
#
# Actions taken:
#   1. Writes /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
#      to prevent cloud-init overwriting network configuration.
#   2. Creates /etc/cloud/cloud-init.disabled (the official disable flag).
#
# Usage:
#   sudo ./disable-cloud-init.sh
#
# Author:            Darren Pilkington
# Version:           1.0
# Date:              31-05-2026
# =============================================================================

set -euo pipefail

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/system-configuration"
LOG_FILE="${LOG_DIR}/disable-cloud-init-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || fail "Run as root: sudo ./disable-cloud-init.sh"

log "Disabling cloud-init on $(hostname -f 2>/dev/null || hostname)"
log "Log file: ${LOG_FILE}"

# ─── Disable cloud-init network configuration ────────────────────────────────
# Prevents cloud-init from overwriting Netplan/network config on reboot
NETWORK_CFG="/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg"
log "Writing network config disable to ${NETWORK_CFG}..."
mkdir -p /etc/cloud/cloud.cfg.d
echo "network: {config: disabled}" > "${NETWORK_CFG}"
log "Network config disable written."

# ─── Set the cloud-init disabled flag ────────────────────────────────────────
# This is the official mechanism: cloud-init checks for this file at startup
DISABLED_FLAG="/etc/cloud/cloud-init.disabled"
log "Creating cloud-init disabled flag: ${DISABLED_FLAG}..."
touch "${DISABLED_FLAG}"
log "Cloud-init disabled flag created."

# ─── Verify ──────────────────────────────────────────────────────────────────
log "Verifying disable..."
[[ -f "${DISABLED_FLAG}" ]] || fail "Disabled flag not found at ${DISABLED_FLAG}."
[[ -f "${NETWORK_CFG}" ]]   || fail "Network config disable not found at ${NETWORK_CFG}."
log "Verification passed — cloud-init will not run on next boot."

log "Cloud-init disable complete. Log: ${LOG_FILE}"
