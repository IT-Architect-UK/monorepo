#!/usr/bin/env bash
# =============================================================================
# Windows Server 2025 Golden Image — Proxmox build wrapper (Linux)
# Runs the Packer build for the win2025-proxmox template. Only requirement on
# this machine is Packer >= 1.10 — provisioning runs in-guest via WinRM.
#
#   1. STANDALONE (interactive):  ./build-win2025-proxmox.sh
#   2. SEMAPHORE JOB (non-interactive) — "Build Golden Image — Windows 2025",
#      created by the Deployment Toolbox bootstrap; Proxmox credentials come
#      from the Semaphore variable group. Set WINRM_PASSWORD there too.
#   3. Pure packer — see the header of win2025-proxmox.pkr.hcl.
#
# Environment variables (prompted when missing and interactive):
#   PROXMOX_HOST / PROXMOX_USER / PROXMOX_TOKEN_ID+SECRET or PROXMOX_PASSWORD
#   PROXMOX_NODE           Proxmox node name
#   WINRM_PASSWORD         MUST match the password inside
#                          http/win2025-proxmox/autounattend.xml
#                          (placeholder default: PackerBuild2025!)
#   PKR_VAR_win_iso_file   volid of the Windows Server 2025 ISO — MANUAL
#                          upload required (Microsoft licensing; grab an eval
#                          ISO from the Microsoft Evaluation Center), e.g.:
#                            local:iso/windows-server-2025.iso
#   PKR_VAR_virtio_iso_file  volid of the virtio-win drivers ISO — staged
#                          AUTOMATICALLY from the stable upstream URL when
#                          unset (see fetch-ubuntu-iso.sh URL mode)
#
# Output: Proxmox template "win2025-golden-<timestamp>" plus a build log
# in ./logs/.
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
command -v packer &>/dev/null || fail "packer not found on PATH"

NONINTERACTIVE=0; [[ ! -t 0 ]] && NONINTERACTIVE=1

# ── Proxmox connection (same contract as the Ubuntu wrappers) ────────────────
# Site defaults from automation/packer/environments/homelab.pkrvars.hcl —
# the one file users edit for their environment; nothing site-specific here.
SITE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../environments" 2>/dev/null && pwd)/homelab.pkrvars.hcl"
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
elif [[ -n "${PROXMOX_PASSWORD:-}" ]]; then
    [[ -n "${PROXMOX_USER:-}" ]] && export PKR_VAR_proxmox_username="${PROXMOX_USER}"
    export PKR_VAR_proxmox_password="${PROXMOX_PASSWORD}"
elif [[ -z "${PKR_VAR_proxmox_password:-}${PKR_VAR_proxmox_token:-}" ]]; then
    [[ "${NONINTERACTIVE}" == "1" ]] && fail "No Proxmox credential (token or password) in environment"
    read -r -s -p "Proxmox password for ${PROXMOX_USER:-root@pam}: " pw; echo
    [[ -n "${PROXMOX_USER:-}" ]] && export PKR_VAR_proxmox_username="${PROXMOX_USER}"
    export PKR_VAR_proxmox_password="${pw}"
fi

# ── WinRM password (must match autounattend.xml) ─────────────────────────────
if [[ -z "${PKR_VAR_winrm_password:-}" ]]; then
    if [[ -n "${WINRM_PASSWORD:-}" ]]; then
        export PKR_VAR_winrm_password="${WINRM_PASSWORD}"
    elif [[ "${NONINTERACTIVE}" == "1" ]]; then
        fail "WINRM_PASSWORD not set (must match http/win2025-proxmox/autounattend.xml)"
    else
        read -r -s -p "WinRM 'packer' password (must match autounattend.xml) [PackerBuild2025!]: " wp; echo
        export PKR_VAR_winrm_password="${wp:-PackerBuild2025!}"
    fi
fi

# ── Windows ISO: pick from storage or upload from a local folder ─────────────
# (Microsoft licensing means no auto-download — but if the ISO is already on
# a Proxmox volume, just select it; otherwise the helper uploads yours.)
if [[ -z "${PKR_VAR_win_iso_file:-}" ]]; then
    [[ "${NONINTERACTIVE}" == "1" ]] \
        && fail "PKR_VAR_win_iso_file not set — required in non-interactive mode"
    log "Choose the Windows Server 2025 ISO (existing on Proxmox, or upload)..."
    SELECT="${SCRIPT_DIR}/../../scripts/select-or-upload-iso.sh"
    VOLID=$(PROXMOX_HOST="${PVE_HOST}" bash "${SELECT}" | tail -1) \
        || fail "ISO selection failed — set PKR_VAR_win_iso_file manually"
    export PKR_VAR_win_iso_file="${VOLID}"
    log "Using Windows ISO: ${VOLID}"
fi

# ── VirtIO drivers ISO: auto-staged from the stable upstream URL ─────────────
if [[ -z "${PKR_VAR_virtio_iso_file:-}" ]]; then
    log "PKR_VAR_virtio_iso_file not set — staging virtio-win.iso on Proxmox..."
    FETCH="${SCRIPT_DIR}/../../scripts/fetch-ubuntu-iso.sh"
    VOLID=$(PROXMOX_HOST="${PVE_HOST}" bash "${FETCH}" \
        "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso" | tail -1) \
        || fail "virtio ISO staging failed — set PKR_VAR_virtio_iso_file manually"
    export PKR_VAR_virtio_iso_file="${VOLID}"
    log "Using virtio ISO: ${VOLID}"
fi

# ── Build ─────────────────────────────────────────────────────────────────────
LOG_DIR="${SCRIPT_DIR}/logs"; mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/build-win2025-$(date '+%Y%m%d-%H%M%S').log"
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
    log "packer init...";     packer init .
    log "packer validate..."; packer validate .
    log "packer build (30-60 min — Windows installs are slow)..."; packer build .
} 2>&1 | tee "${LOG_FILE}"
log "Done. New template: win2025-golden-<timestamp> in Proxmox."
