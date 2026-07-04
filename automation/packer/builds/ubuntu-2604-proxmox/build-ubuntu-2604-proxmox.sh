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

# First breath before strict mode: if this script ever dies, these two lines
# guarantee it can never do so silently — the banner proves it started, and
# the ERR trap names the exact line and command that killed it.
echo "[$(basename "${BASH_SOURCE[0]:-$0}")] starting as $(id -un 2>/dev/null || echo '?') in $(pwd)"
set -euo pipefail
trap 's=$?; echo "[$(basename "${BASH_SOURCE[0]:-$0}")] FATAL exit=$s at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

command -v packer  &>/dev/null || fail "packer not found on PATH"
command -v xorriso &>/dev/null || fail "xorriso not found — Packer needs it to build the cidata/unattend CD. Install it: sudo apt-get update && sudo apt-get install -y xorriso (baked into toolbox images from the next rebuild)"

NONINTERACTIVE=0; [[ ! -t 0 ]] && NONINTERACTIVE=1   # no TTY (e.g. Semaphore) = no prompts

# ── Map connection env vars to Packer vars (env-first, prompt-fallback) ──────
# Site defaults from automation/packer/environments/homelab.pkrvars.hcl —
# the one file users edit for their environment; nothing site-specific here.
# NB: built from the absolute SCRIPT_DIR — deriving it from the relative
# BASH_SOURCE after cd'ing broke under Semaphore (caught by the ERR trap).
SITE_FILE="${SCRIPT_DIR}/../../environments/homelab.pkrvars.hcl"
SITE_HOST=""
[[ -f "${SITE_FILE}" ]] && SITE_HOST="$(grep -E '^\s*proxmox_url\s*=' "${SITE_FILE}" | head -1 | sed -E 's/^[^=]*=\s*"?([^"#]*[^"# ])"?.*$/\1/' | sed -E 's#^https?://##; s#[:/].*$##')"
PVE_HOST="${PROXMOX_HOST:-}"
if [[ -z "${PVE_HOST}" && -z "${PKR_VAR_proxmox_url:-}" ]]; then
    if [[ "${NONINTERACTIVE}" == "1" ]]; then
        [[ -n "${SITE_HOST}" ]] && PVE_HOST="${SITE_HOST}" || fail "PROXMOX_HOST not set"
    elif [[ -n "${SITE_HOST}" ]]; then
        read -r -p "Proxmox API host [${SITE_HOST}]: " PVE_HOST
        PVE_HOST="${PVE_HOST:-${SITE_HOST}}"
    else
        read -r -p "Proxmox API host: " PVE_HOST
        [[ -n "${PVE_HOST}" ]] || fail "A Proxmox API host is required"
    fi
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
# Temp dir must be SHORT: Packer plugins bind a unix socket in TMPDIR and
# the kernel caps socket paths at ~108 chars — a deep checkout path kills
# plugins with "plugin exited before we could connect" (hit on a real run).
# Prefer /tmp when writable; otherwise a short .tmp at the repo root.
if touch /tmp/.pkr-write-test 2>/dev/null; then
    rm -f /tmp/.pkr-write-test
    PKR_TMP="/tmp"
else
    PKR_TMP="$(cd "${SCRIPT_DIR}/../../../.." && pwd)/.tmp"
    mkdir -p "${PKR_TMP}"
fi
export TMPDIR="${PKR_TMP}"
export PACKER_TMP_DIR="${PKR_TMP}"          # Packer's own temp-dir knob — takes precedence
export PACKER_CONFIG_DIR="${SCRIPT_DIR}/.packer"
export PACKER_PLUGIN_PATH="${SCRIPT_DIR}/.packer/plugins"
export PACKER_CACHE_DIR="${SCRIPT_DIR}/.packer/cache"
mkdir -p "${PACKER_PLUGIN_PATH}" "${PACKER_CACHE_DIR}"

# Self-diagnosis: every run states exactly which code and paths it uses, so
# a stale Semaphore repo cache or env problem is visible at a glance.
log "Wrapper commit : $(git -C "${SCRIPT_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
log "Packer temp    : ${TMPDIR} ($(echo -n "${TMPDIR}" | wc -c) chars — must stay well under 108)"
# Full Packer debug log alongside the build log — invaluable when a plugin
# dies before it can talk (gitignored with the rest of logs/).
export PACKER_LOG=1
export PACKER_LOG_PATH="${LOG_FILE%.log}-packer-debug.log"

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
