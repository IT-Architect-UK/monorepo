#!/usr/bin/env bash
# =============================================================================
# remove-vm-if-exists.sh — delete a Proxmox VM or template by VMID, if present
#
# Golden-image builds use a FIXED VMID per OS (so clones always reference a
# known template). The proxmox-iso Packer plugin has no "force" option and
# aborts if that VMID is already taken, which makes re-running a build fail.
# This helper clears the slot first, so "re-run the build" means "rebuild in
# place" — the old template is removed just before the new one is created.
#
# It is IDEMPOTENT: if the VMID is not present it succeeds silently. It is
# also standalone — run it by hand to delete a stray build VM/template.
#
# Usage:
#   VM_ID=9003 ./remove-vm-if-exists.sh
#   ./remove-vm-if-exists.sh 9003
#
# Environment (same contract as select-or-upload-iso.sh / fetch-ubuntu-iso.sh):
#   PROXMOX_HOST           Proxmox API host (falls back to the site file)
#   PROXMOX_USER           API user [default: root@pam / site file]
#   PROXMOX_TOKEN_ID       API token id     ) token auth (recommended)
#   PROXMOX_TOKEN_SECRET   API token secret )
#   PROXMOX_PASSWORD       password (ticket auth, used if no token is set)
#   PROXMOX_NODE           node name (optional — auto-located cluster-wide)
#
# Site defaults come from the ONE user-edited site file (no lab values are
# hardcoded here): automation/packer/environments/homelab.pkrvars.hcl
#
# The token/password must carry VM.Allocate on the node — the same right the
# build itself needs to CREATE the VM, so if the build can run, this can too.
#
# Requirements: bash, curl, jq.
#
# Author:            Darren Pilkington
# Version:           1.0
# Date:              06-07-2026
# =============================================================================

echo "[$(basename "${BASH_SOURCE[0]:-$0}")] starting as $(id -un 2>/dev/null || echo '?') in $(pwd)"
set -euo pipefail
trap 's=$?; echo "[$(basename "${BASH_SOURCE[0]:-$0}")] FATAL exit=$s at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" >&2; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; exit 1; }
command -v curl &>/dev/null || fail "curl not found"
command -v jq   &>/dev/null || fail "jq not found"

VMID="${1:-${VM_ID:-}}"
[[ -n "${VMID}" ]] || fail "No VMID given (pass as arg 1 or set VM_ID)"
[[ "${VMID}" =~ ^[0-9]+$ ]] || fail "VMID must be numeric (got '${VMID}')"

# --- Connection (same contract as the ISO helpers) --------------------------
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SITE_FILE="${SELF_DIR}/../environments/homelab.pkrvars.hcl"
site_val() { # site_val <pkrvars-key>
    [[ -f "${SITE_FILE}" ]] || return 0
    grep -E "^\s*${1}\s*=" "${SITE_FILE}" | head -1 | sed -E 's/^[^=]*=\s*"?([^"#]*[^"# ])"?.*$/\1/'
}
SITE_HOST="$(site_val proxmox_url | sed -E 's#^https?://##; s#[:/].*$##')"
PVE_HOST="${PROXMOX_HOST:-${SITE_HOST}}"
[[ -n "${PVE_HOST}" ]] || fail "PROXMOX_HOST not set and no proxmox_url in the site file"
PVE_USER="${PROXMOX_USER:-$(site_val proxmox_username)}"
PVE_USER="${PVE_USER:-root@pam}"
API="https://${PVE_HOST}:8006/api2/json"

AUTH_HEADER=""; COOKIE=""; CSRF=""
if [[ -n "${PROXMOX_TOKEN_ID:-}" && -n "${PROXMOX_TOKEN_SECRET:-}" ]]; then
    AUTH_HEADER="Authorization: PVEAPIToken=${PVE_USER}!${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}"
else
    PVE_PASS="${PROXMOX_PASSWORD:-}"
    [[ -n "${PVE_PASS}" ]] || fail "No Proxmox credential (PROXMOX_TOKEN_ID/SECRET or PROXMOX_PASSWORD)"
    TICKET_JSON=$(curl -fsSk --max-time 15 -X POST "${API}/access/ticket" \
        --data-urlencode "username=${PVE_USER}" --data-urlencode "password=${PVE_PASS}") \
        || fail "Proxmox authentication failed"
    COOKIE="PVEAuthCookie=$(echo "${TICKET_JSON}" | jq -r '.data.ticket')"
    CSRF=$(echo "${TICKET_JSON}" | jq -r '.data.CSRFPreventionToken')
fi
pve() { local method="$1" path="$2"; shift 2
    if [[ -n "${AUTH_HEADER}" ]]; then
        curl -fsSk --max-time 120 -X "${method}" -H "${AUTH_HEADER}" "$@" "${API}${path}"
    else
        curl -fsSk --max-time 120 -X "${method}" -b "${COOKIE}" -H "CSRFPreventionToken: ${CSRF}" "$@" "${API}${path}"
    fi
}
pve GET /version >/dev/null \
    || fail "Proxmox rejected the credential (user=${PVE_USER}${PROXMOX_TOKEN_ID:+, token=${PROXMOX_TOKEN_ID}}). Check PROXMOX_USER matches the token's OWNER."

# --- Locate the VMID cluster-wide (tells us its node + run state) ------------
vm_row() { pve GET "/cluster/resources?type=vm" | jq -c --argjson id "${VMID}" '.data[] | select(.vmid == $id)'; }
ROW="$(vm_row || true)"
if [[ -z "${ROW}" ]]; then
    log "VMID ${VMID} is not present — nothing to remove"
    exit 0
fi
NODE=$(echo "${ROW}" | jq -r '.node')
STATUS=$(echo "${ROW}" | jq -r '.status')
IS_TMPL=$(echo "${ROW}" | jq -r '.template // 0')
log "VMID ${VMID} found on ${NODE} (status=${STATUS}, template=${IS_TMPL}) — removing"

# A template never runs, but a half-finished build VM might still be up.
if [[ "${STATUS}" == "running" ]]; then
    log "Stopping VMID ${VMID}..."
    pve POST "/nodes/${NODE}/qemu/${VMID}/status/stop" >/dev/null || true
    for _ in $(seq 1 30); do
        s=$(pve GET "/cluster/resources?type=vm" | jq -r --argjson id "${VMID}" '.data[]|select(.vmid==$id).status')
        [[ "${s}" != "running" ]] && break
        sleep 2
    done
fi

pve DELETE "/nodes/${NODE}/qemu/${VMID}?purge=1&destroy-unreferenced-disks=1" >/dev/null \
    || fail "Failed to delete VMID ${VMID} on ${NODE} (does the token carry VM.Allocate?)"

# The DELETE is an async Proxmox task — wait until the VMID actually clears so
# the caller doesn't try to create a new VM on a slot that's still occupied.
for _ in $(seq 1 30); do
    if [[ -z "$(vm_row || true)" ]]; then
        log "VMID ${VMID} removed"
        exit 0
    fi
    sleep 2
done
fail "VMID ${VMID} still present ~60s after delete — aborting rather than build on a stale slot"
