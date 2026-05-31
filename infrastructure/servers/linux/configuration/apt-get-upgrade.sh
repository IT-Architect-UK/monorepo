#!/usr/bin/env bash
# =============================================================================
# System Package Upgrade — Ubuntu
# Performs a full non-interactive system upgrade: updates package lists,
# upgrades all installed packages, removes obsolete dependencies, and
# cleans the local package cache.
#
# Intended to be run as part of a post-deployment baseline or on a schedule
# via cron. Safe to run repeatedly — fully idempotent.
#
# Usage:
#   sudo ./apt-get-upgrade.sh
#
# Author:            Darren Pilkington
# Version:           1.0
# Date:              31-05-2026
# =============================================================================

set -euo pipefail

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/system-upgrade"
LOG_FILE="${LOG_DIR}/apt-upgrade-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || fail "Run as root: sudo ./apt-get-upgrade.sh"
command -v apt-get &>/dev/null || fail "apt-get not found — Debian/Ubuntu required."

log "System upgrade starting on $(hostname -f 2>/dev/null || hostname)"
log "Log file: ${LOG_FILE}"

# ─── Update package lists ────────────────────────────────────────────────────
log "Updating package lists..."
apt-get update -y 2>&1 | tee -a "${LOG_FILE}"
log "Package lists updated."

# ─── Upgrade installed packages ──────────────────────────────────────────────
log "Upgrading installed packages (non-interactive)..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold" \
    2>&1 | tee -a "${LOG_FILE}"
log "Package upgrade complete."

# ─── Remove obsolete dependencies ────────────────────────────────────────────
log "Removing obsolete dependencies..."
DEBIAN_FRONTEND=noninteractive apt-get autoremove -y 2>&1 | tee -a "${LOG_FILE}"
log "Autoremove complete."

# ─── Clean local package cache ───────────────────────────────────────────────
log "Cleaning local package cache..."
apt-get autoclean -y 2>&1 | tee -a "${LOG_FILE}"
log "Cache clean complete."

log "System upgrade finished successfully. Log: ${LOG_FILE}"
