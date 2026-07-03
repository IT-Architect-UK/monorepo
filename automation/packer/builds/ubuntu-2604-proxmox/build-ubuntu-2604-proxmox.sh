#!/usr/bin/env bash
# =============================================================================
# Ubuntu 26.04 Golden Image — Proxmox build wrapper (Linux)
# Runs the Packer build for the ubuntu-2604-proxmox template. Works three ways:
#
#   1. STANDALONE (interactive) — any Linux box with packer + ansible:
#        ./build-ubuntu-2604-proxmox.sh
#      Missing values are prompted for; everything else has sane defaults.
#
#   2. SEMAPHORE JOB (non-interactive) — the Deployment Toolbox bootstrap
#      creates a "Build Golden Image — Ubuntu 26.04" task template that runs
#      this script with the Proxmox variable group providing credentials.
#
#   3. Pure packer — see the header of ubuntu-2604-proxmox.pkr.hcl.
#
# Environment variables (all optional interactively, required for CI use):
#   PROXMOX_HOST           API host/IP (no scheme) — becomes proxmox_url
#   PROXMOX_USER           e.g. root@pam
#   PROXMOX_TOKEN_ID       API token ID   (token auth — recommended)
#   PROXMOX_TOKEN_SECRET   API token secret
#   PROXMOX_PASSWORD       Password (only if not using a token)
#   PROXMOX_NODE           Proxmox node name
#   PKR_VAR_*              Any Packer variable can be overridden directly
#
# Prerequisites:
#   - packer >= 1.10 on THIS machine — the only requirement (the Ansible
#     baseline runs inside the build VM, not here)
#   - The Ubuntu ISO is staged AUTOMATICALLY: if PKR_VAR_ubuntu_iso_file is
#     unset, fetch-ubuntu-iso.sh finds the latest 26.04 live-server image and
#     has Proxmox download it server-side (storage chosen interactively, or
#     via ISO_STORAGE). To pin a specific pre-uploaded ISO instead:
#       export PKR_VAR_ubuntu_iso_file="local:iso/ubuntu-26.04.2-live-server-amd64.iso"
#
# Output: Proxmox template "ubuntu-2604-golden-<timestamp>" (VMID 9006 by
# default) plus a timestamped build log in ./logs/.
#
# Author:            Darren Pilkington
# Version:           1.0
# Date:              02-07-2026
# =============================================================================

set -euo pipefail

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

command -v packer &>/dev/null || fail "packer not found on PATH (the ONLY build-host requirement — Ansible runs inside the guest)"

NONINTERACTIVE=0; [[ ! -t 0 ]] && NONINTERACTIVE=1   # no TTY (e.g. Semaphore) = no prompts

# ── Map connection env vars to Packer vars (env-first, prompt-fallback) ──────
PVE_HOST="${PROXMOX_HOST:-}"
if [[ -z "${PVE_HOST}" && -z "${PKR_VAR_proxmox_url:-}" ]]; then
    [[ "${NONINTERACTIVE}" == "1" ]] && fail "PROXMOX_HOST not set"
    read -r -p "Proxmox API host [192.168.4.150]: " PVE_HOST
    PVE_HOST="${PVE_HOST:-192.168.4.150}"
fi
[[ -n "${PVE_HOST}" ]] && export PKR_VAR_proxmox_url="https://${PVE_HOST}:8006/api2/json"

[[ -n "${PROXMOX_NODE:-}" ]] && export PKR_VAR_proxmox_node="${PROXMOX_NODE}"

if [[ -n "${PROXMOX_TOKEN_ID:-}" && -n "${PROXMOX_TOKEN_SECRET:-}" ]]; then
    export PKR_VAR_proxmox_username="${PROXMOX_USER:-root@pam}!${PROXMOX_TOKEN_ID}"
    export PKR_VAR_proxmox_token="${PROXMOX_TOKEN_SECRET}"
    log "Authenticating with API token ${PKR_VAR_proxmox_username}"
elif [[ -n "${PROXMOX_PASSWORD:-}" ]]; then
    [[ -n "${PROXMOX_USER:-}" ]] && export PKR_VAR_proxmox_username="${PROXMOX_USER}"
    export PKR_VAR_proxmox_password="${PROXMOX_PASSWORD}"
elif [[ -z "${PKR_VAR_proxmox_password:-}${PKR_VAR_proxmox_token:-}" ]]; then
    [[ "${NONINTERACTIVE}" == "1" ]] && fail "No Proxmox credential (token or password) in environment"
    read -r -s -p "Proxmox password for ${PROXMOX_USER:-root@pam}: " pw; echo
    [[ -n "${PROXMOX_USER:-}" ]] && export PKR_VAR_proxmox_username="${PROXMOX_USER}"
    export PKR_VAR_proxmox_password="${pw}"
fi

# ── ISO: auto-stage the latest 26.04 image if none specified ─────────────────
if [[ -z "${PKR_VAR_ubuntu_iso_file:-}" ]]; then
    log "PKR_VAR_ubuntu_iso_file not set — staging the latest Ubuntu 26.04 ISO on Proxmox..."
    FETCH="${SCRIPT_DIR}/../../scripts/fetch-ubuntu-iso.sh"
    [[ -f "${FETCH}" ]] || fail "fetch-ubuntu-iso.sh not found at ${FETCH}"
    VOLID=$(PROXMOX_HOST="${PVE_HOST}" bash "${FETCH}" 26.04 | tail -1)         || fail "ISO staging failed — set PKR_VAR_ubuntu_iso_file manually (see header)"
    export PKR_VAR_ubuntu_iso_file="${VOLID}"
    log "Using ISO: ${VOLID}"
fi

# ── Build ─────────────────────────────────────────────────────────────────────
LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/build-ubuntu-2604-$(date '+%Y%m%d-%H%M%S').log"
log "Build log: ${LOG_FILE}"

# Keep ALL of Packer's writable state inside this build directory: the
# Semaphore service (and other hardened environments) mount /tmp read-only
# and block $HOME, which otherwise kills packer's log tempfile and plugin
# install. Self-contained dirs work everywhere. (.packer/ is gitignored.)
export TMPDIR="${LOG_DIR}"
export PACKER_CONFIG_DIR="${SCRIPT_DIR}/.packer"
export PACKER_PLUGIN_PATH="${SCRIPT_DIR}/.packer/plugins"
mkdir -p "${PACKER_PLUGIN_PATH}"

export PACKER_NO_COLOR=1
{
    log "packer init..."
    packer init .
    log "packer validate..."
    packer validate .
    log "packer build (15-30 min)..."
    packer build .
} 2>&1 | tee "${LOG_FILE}"

log "Done. New template: check 'ubuntu-2604-golden-<timestamp>' (VMID 9006) in Proxmox."
log "Provision from it via Semaphore: Task Templates -> Provision VM (Proxmox)."
