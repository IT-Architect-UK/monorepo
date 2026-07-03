#!/usr/bin/env bash
# =============================================================================
# fetch-ubuntu-iso.sh — Stage the latest Ubuntu server ISO on Proxmox storage
#
# Finds the newest live-server ISO for a given Ubuntu release, lets you pick
# which Proxmox storage to put it on, and has PROXMOX ITSELF download and
# checksum-verify it (server-side pull via the download-url API) — nothing
# large ever passes through the machine running this script.
#
# Idempotent: if the ISO is already present on the chosen storage, nothing
# is downloaded and the existing volid is returned.
#
# Usage (standalone):
#   ./fetch-ubuntu-iso.sh 24.04
#   ./fetch-ubuntu-iso.sh 26.04
#
# Usage (scripted/CI — no prompts, e.g. from Semaphore or build wrappers):
#   PROXMOX_HOST=192.0.2.10 PROXMOX_USER=root@pam \
#   PROXMOX_TOKEN_ID=automation PROXMOX_TOKEN_SECRET=... \
#   ISO_STORAGE=local ./fetch-ubuntu-iso.sh 24.04
#
# Environment variables (prompted for when missing and interactive):
#   PROXMOX_HOST           API host/IP (no scheme)
#   PROXMOX_USER           e.g. root@pam                [default: root@pam]
#   PROXMOX_TOKEN_ID       API token ID (token auth — recommended)
#   PROXMOX_TOKEN_SECRET   API token secret
#   PROXMOX_PASSWORD       Password (only if not using a token)
#   PROXMOX_NODE           Node name                    [default: first node]
#   ISO_STORAGE            Target storage; when unset: interactive menu of
#                          ISO-capable storages, or (non-interactive) the one
#                          with the most free space
#
# Output: the LAST line on stdout is the volid, e.g.
#   local:iso/ubuntu-24.04.2-live-server-amd64.iso
# so callers can do:  VOLID=$(./fetch-ubuntu-iso.sh 24.04 | tail -1)
#
# Requirements: bash, curl, jq.
#
# Author:            Darren Pilkington
# Version:           1.0
# Date:              02-07-2026
# =============================================================================

set -euo pipefail

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" >&2; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" >&2; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; exit 1; }

command -v curl &>/dev/null || fail "curl not found"
command -v jq   &>/dev/null || fail "jq not found"

# Two modes:
#   <release>  e.g. 24.04 — discover the latest Ubuntu live-server ISO
#   <url>      any direct http(s) ISO URL (e.g. the virtio-win drivers ISO) —
#              staged as-is, no checksum (add one upstream when available)
RELEASE="${1:-}"
DIRECT_URL=""
if [[ "${RELEASE}" =~ ^https?:// ]]; then
    DIRECT_URL="${RELEASE}"
elif [[ ! "${RELEASE}" =~ ^[0-9]{2}\.[0-9]{2}$ ]]; then
    fail "Usage: $0 <release|url>   e.g. $0 24.04   or   $0 https://host/path/some.iso"
fi

NONINTERACTIVE=0; [[ ! -t 0 ]] && NONINTERACTIVE=1

# ─── 1. Determine what to download ───────────────────────────────────────────
if [[ -n "${DIRECT_URL}" ]]; then
    ISO_URL="${DIRECT_URL}"
    ISO_NAME="$(basename "${DIRECT_URL}")"
    ISO_SHA256=""
    log "Direct URL mode: ${ISO_NAME}"
else
MIRROR="https://releases.ubuntu.com/${RELEASE}"
log "Checking ${MIRROR} for the latest live-server ISO..."
SUMS=$(curl -fsSL --max-time 30 "${MIRROR}/SHA256SUMS") \
    || fail "Could not fetch ${MIRROR}/SHA256SUMS — is ${RELEASE} a published release?"

ISO_NAME=$(echo "${SUMS}" | grep -oE "ubuntu-${RELEASE}(\.[0-9]+)?-live-server-amd64\.iso" | sort -V | tail -1)
[[ -n "${ISO_NAME}" ]] || fail "No live-server-amd64 ISO found in ${MIRROR}/SHA256SUMS"
ISO_SHA256=$(echo "${SUMS}" | grep -F "${ISO_NAME}" | awk '{print $1}' | head -1)
ISO_URL="${MIRROR}/${ISO_NAME}"
log "Latest: ${ISO_NAME}"
log "SHA256: ${ISO_SHA256}"
fi

# ─── 2. Proxmox connection ───────────────────────────────────────────────────
# Site defaults come from the ONE user-edited site file (no lab-specific
# values hardcoded here): automation/packer/environments/homelab.pkrvars.hcl
SITE_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../environments" 2>/dev/null && pwd)/homelab.pkrvars.hcl"
site_val() { # site_val <pkrvars-key>
    [[ -f "${SITE_FILE}" ]] || return 0
    grep -E "^\s*${1}\s*=" "${SITE_FILE}" | head -1 | sed -E 's/^[^=]*=\s*"?([^"#]*[^"# ])"?.*$/\1/'
}
SITE_HOST="$(site_val proxmox_url | sed -E 's#^https?://##; s#[:/].*$##')"
PVE_HOST="${PROXMOX_HOST:-}"
if [[ -z "${PVE_HOST}" ]]; then
    [[ "${NONINTERACTIVE}" == "1" && -z "${SITE_HOST}" ]] && fail "PROXMOX_HOST not set"
    if [[ "${NONINTERACTIVE}" == "1" ]]; then
        PVE_HOST="${SITE_HOST}"
    elif [[ -n "${SITE_HOST}" ]]; then
        read -r -p "Proxmox API host [${SITE_HOST}]: " PVE_HOST
        PVE_HOST="${PVE_HOST:-${SITE_HOST}}"
    else
        read -r -p "Proxmox API host: " PVE_HOST
        [[ -n "${PVE_HOST}" ]] || fail "A Proxmox API host is required"
    fi
fi
PVE_USER="${PROXMOX_USER:-$(site_val proxmox_username)}"
PVE_USER="${PVE_USER:-root@pam}"
API="https://${PVE_HOST}:8006/api2/json"

AUTH_HEADER=""
COOKIE=""
CSRF=""
if [[ -n "${PROXMOX_TOKEN_ID:-}" && -n "${PROXMOX_TOKEN_SECRET:-}" ]]; then
    AUTH_HEADER="Authorization: PVEAPIToken=${PVE_USER}!${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}"
    log "Authenticating with API token ${PVE_USER}!${PROXMOX_TOKEN_ID}"
else
    PVE_PASS="${PROXMOX_PASSWORD:-}"
    if [[ -z "${PVE_PASS}" ]]; then
        [[ "${NONINTERACTIVE}" == "1" ]] && fail "No Proxmox credential (PROXMOX_TOKEN_ID/SECRET or PROXMOX_PASSWORD)"
        read -r -s -p "Proxmox password for ${PVE_USER}: " PVE_PASS; echo >&2
    fi
    TICKET_JSON=$(curl -fsSk --max-time 15 -X POST "${API}/access/ticket" \
        --data-urlencode "username=${PVE_USER}" --data-urlencode "password=${PVE_PASS}") \
        || fail "Proxmox authentication failed"
    COOKIE="PVEAuthCookie=$(echo "${TICKET_JSON}" | jq -r '.data.ticket')"
    CSRF=$(echo "${TICKET_JSON}" | jq -r '.data.CSRFPreventionToken')
fi

pve() { # pve METHOD PATH [curl-data-args...]
    local method="$1" path="$2"; shift 2
    if [[ -n "${AUTH_HEADER}" ]]; then
        curl -fsSk --max-time 60 -X "${method}" -H "${AUTH_HEADER}" "$@" "${API}${path}"
    else
        curl -fsSk --max-time 60 -X "${method}" -b "${COOKIE}" -H "CSRFPreventionToken: ${CSRF}" "$@" "${API}${path}"
    fi
}

# ─── 3. Node ─────────────────────────────────────────────────────────────────
# Probe the credential early with a clear message — a 401 here almost always
# means PROXMOX_USER doesn't match the token's owner (e.g. claude@pam token
# entered with the root@pam default).
pve GET /version >/dev/null \
    || fail "Proxmox rejected the credential (user=${PVE_USER}${PROXMOX_TOKEN_ID:+, token=${PROXMOX_TOKEN_ID}}). Check that PROXMOX_USER matches the token's OWNER."

PVE_NODE="${PROXMOX_NODE:-}"
if [[ -z "${PVE_NODE}" ]]; then
    PVE_NODE=$(pve GET /nodes | jq -r '.data[0].node')
    [[ -n "${PVE_NODE}" && "${PVE_NODE}" != "null" ]] || fail "Could not determine Proxmox node"
    log "Node not specified — using '${PVE_NODE}'"
fi

# ─── 4. Choose ISO-capable storage ───────────────────────────────────────────
STORAGES_JSON=$(pve GET "/nodes/${PVE_NODE}/storage?content=iso&enabled=1")
mapfile -t STORAGE_LINES < <(echo "${STORAGES_JSON}" | jq -r '.data[] | "\(.storage)\t\(.avail // 0)"' | sort -k2 -nr)
[[ ${#STORAGE_LINES[@]} -gt 0 ]] || fail "No ISO-capable storage found on node ${PVE_NODE}"

STORAGE="${ISO_STORAGE:-}"
if [[ -z "${STORAGE}" ]]; then
    if [[ "${NONINTERACTIVE}" == "1" ]]; then
        STORAGE=$(echo -e "${STORAGE_LINES[0]}" | cut -f1)
        log "ISO_STORAGE not set — using '${STORAGE}' (most free space)"
    else
        echo "" >&2
        echo "ISO-capable storage on ${PVE_NODE}:" >&2
        local_i=1
        for line in "${STORAGE_LINES[@]}"; do
            name=$(echo -e "${line}" | cut -f1); avail=$(echo -e "${line}" | cut -f2)
            printf "  %d) %-20s %6s GB free\n" "${local_i}" "${name}" "$(( avail / 1024 / 1024 / 1024 ))" >&2
            local_i=$(( local_i + 1 ))
        done
        read -r -p "Choose storage [1]: " choice
        choice="${choice:-1}"
        [[ "${choice}" =~ ^[0-9]+$ && "${choice}" -ge 1 && "${choice}" -le ${#STORAGE_LINES[@]} ]] || fail "Invalid choice"
        STORAGE=$(echo -e "${STORAGE_LINES[$(( choice - 1 ))]}" | cut -f1)
    fi
fi
log "Target storage: ${STORAGE}"
VOLID="${STORAGE}:iso/${ISO_NAME}"

# ─── 5. Skip if already present ──────────────────────────────────────────────
if pve GET "/nodes/${PVE_NODE}/storage/${STORAGE}/content?content=iso" \
    | jq -e --arg v "${VOLID}" '.data[] | select(.volid == $v)' >/dev/null; then
    log "ISO already present — nothing to download."
    echo "${VOLID}"
    exit 0
fi

# ─── 6. Server-side download (Proxmox pulls and verifies it) ─────────────────
log "Asking Proxmox to download ${ISO_NAME} to '${STORAGE}' (~3 GB, this can take a while)..."
CHECKSUM_ARGS=()
[[ -n "${ISO_SHA256}" ]] && CHECKSUM_ARGS=(--data-urlencode "checksum=${ISO_SHA256}" --data-urlencode "checksum-algorithm=sha256")
UPID=$(pve POST "/nodes/${PVE_NODE}/storage/${STORAGE}/download-url" \
    --data-urlencode "content=iso" \
    --data-urlencode "filename=${ISO_NAME}" \
    --data-urlencode "url=${ISO_URL}" \
    "${CHECKSUM_ARGS[@]}" | jq -r '.data')
[[ -n "${UPID}" && "${UPID}" != "null" ]] || fail "download-url did not return a task ID"

ELAPSED=0; TIMEOUT=2700
while (( ELAPSED < TIMEOUT )); do
    sleep 10; ELAPSED=$(( ELAPSED + 10 ))
    STATUS_JSON=$(pve GET "/nodes/${PVE_NODE}/tasks/${UPID}/status")
    STATUS=$(echo "${STATUS_JSON}" | jq -r '.data.status')
    if [[ "${STATUS}" == "stopped" ]]; then
        EXIT=$(echo "${STATUS_JSON}" | jq -r '.data.exitstatus')
        [[ "${EXIT}" == "OK" ]] || fail "Proxmox download task failed: ${EXIT} (task ${UPID})"
        log "Download complete and checksum verified."
        echo "${VOLID}"
        exit 0
    fi
    (( ELAPSED % 60 == 0 )) && log "  still downloading... (${ELAPSED}s)"
done
fail "Download did not finish within $(( TIMEOUT / 60 )) minutes (task ${UPID})"
