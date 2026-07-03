#!/usr/bin/env bash
# =============================================================================
# select-or-upload-iso.sh — Pick an existing ISO on Proxmox storage, or
# upload one from a local folder
#
# Interactive helper for build wrappers (and standalone use): enumerates the
# node's ISO-capable storages, lists the ISOs already on the chosen storage
# for selection by number, or uploads a local .iso file to it via the
# Proxmox API.
#
# Usage (standalone):
#   ./select-or-upload-iso.sh                # walk through storage + ISO
#
# Environment variables (prompted for when missing):
#   PROXMOX_HOST / PROXMOX_USER / PROXMOX_TOKEN_ID+SECRET or PROXMOX_PASSWORD
#   PROXMOX_NODE           Node name [default: first node]
#   ISO_STORAGE            Skip the storage menu
#
# Output: the LAST line on stdout is the chosen/uploaded volid, e.g.
#   NFS-10GB-PROXMOX-1:iso/Windows-Server-2025.ISO
#
# Non-interactive use is not supported (selection needs a human) — scripted
# callers should set the PKR_VAR_*_iso_file variable directly instead.
#
# Requirements: bash, curl, jq.
#
# Author:            Darren Pilkington
# Version:           1.0
# Date:              02-07-2026
# =============================================================================

set -euo pipefail
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" >&2; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; exit 1; }
command -v curl &>/dev/null || fail "curl not found"
command -v jq   &>/dev/null || fail "jq not found"
[[ -t 0 ]] || fail "This helper is interactive — set the ISO volid via environment for scripted use."

# ─── Connection (same contract as fetch-ubuntu-iso.sh) ───────────────────────
PVE_HOST="${PROXMOX_HOST:-}"
if [[ -z "${PVE_HOST}" ]]; then
    read -r -p "Proxmox API host [192.168.4.150]: " PVE_HOST
    PVE_HOST="${PVE_HOST:-192.168.4.150}"
fi
PVE_USER="${PROXMOX_USER:-root@pam}"
API="https://${PVE_HOST}:8006/api2/json"
AUTH_HEADER=""; COOKIE=""; CSRF=""
if [[ -n "${PROXMOX_TOKEN_ID:-}" && -n "${PROXMOX_TOKEN_SECRET:-}" ]]; then
    AUTH_HEADER="Authorization: PVEAPIToken=${PVE_USER}!${PROXMOX_TOKEN_ID}=${PROXMOX_TOKEN_SECRET}"
else
    PVE_PASS="${PROXMOX_PASSWORD:-}"
    if [[ -z "${PVE_PASS}" ]]; then
        read -r -s -p "Proxmox password for ${PVE_USER}: " PVE_PASS; echo >&2
    fi
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

# Probe the credential early with a clear message — a 401 here almost always
# means PROXMOX_USER doesn't match the token's owner (e.g. claude@pam token
# entered with the root@pam default).
pve GET /version >/dev/null \
    || fail "Proxmox rejected the credential (user=${PVE_USER}${PROXMOX_TOKEN_ID:+, token=${PROXMOX_TOKEN_ID}}). Check that PROXMOX_USER matches the token's OWNER."

PVE_NODE="${PROXMOX_NODE:-}"
[[ -z "${PVE_NODE}" ]] && PVE_NODE=$(pve GET /nodes | jq -r '.data[0].node')

# ─── Storage menu ────────────────────────────────────────────────────────────
STORAGE="${ISO_STORAGE:-}"
mapfile -t STORAGE_LINES < <(pve GET "/nodes/${PVE_NODE}/storage?content=iso&enabled=1" \
    | jq -r '.data[] | "\(.storage)\t\(.avail // 0)"' | sort -k2 -nr)
[[ ${#STORAGE_LINES[@]} -gt 0 ]] || fail "No ISO-capable storage on node ${PVE_NODE}"
if [[ -z "${STORAGE}" ]]; then
    echo "" >&2; echo "ISO-capable storage on ${PVE_NODE}:" >&2
    i=1; for line in "${STORAGE_LINES[@]}"; do
        printf "  %d) %-24s %6s GB free\n" "$i" "$(cut -f1 <<<"${line}")" "$(( $(cut -f2 <<<"${line}") / 1073741824 ))" >&2
        i=$(( i + 1 ))
    done
    read -r -p "Choose storage [1]: " c; c="${c:-1}"
    [[ "$c" =~ ^[0-9]+$ && "$c" -ge 1 && "$c" -le ${#STORAGE_LINES[@]} ]] || fail "Invalid choice"
    STORAGE=$(cut -f1 <<<"${STORAGE_LINES[$(( c - 1 ))]}")
fi
log "Storage: ${STORAGE}"

# ─── ISO menu (existing) or upload ───────────────────────────────────────────
mapfile -t ISO_LINES < <(pve GET "/nodes/${PVE_NODE}/storage/${STORAGE}/content?content=iso" \
    | jq -r '.data[] | "\(.volid)\t\(.size // 0)"' | sort)
echo "" >&2; echo "ISOs on ${STORAGE}:" >&2
i=1; for line in "${ISO_LINES[@]}"; do
    printf "  %d) %-60s %5s GB\n" "$i" "$(cut -f1 <<<"${line}")" "$(( $(cut -f2 <<<"${line}") / 1073741824 ))" >&2
    i=$(( i + 1 ))
done
echo "  u) Upload a .iso from a local folder" >&2
read -r -p "Choose an ISO, or 'u' to upload: " c
if [[ "${c}" =~ ^[0-9]+$ && "${c}" -ge 1 && "${c}" -le ${#ISO_LINES[@]} ]]; then
    cut -f1 <<<"${ISO_LINES[$(( c - 1 ))]}"
    exit 0
fi
[[ "${c}" =~ ^[Uu]$ ]] || fail "Invalid choice"

read -r -e -p "Path to local .iso file: " LOCAL_ISO
LOCAL_ISO="${LOCAL_ISO/#\~/$HOME}"
[[ -f "${LOCAL_ISO}" ]] || fail "File not found: ${LOCAL_ISO}"
FNAME="$(basename "${LOCAL_ISO}")"
log "Uploading ${FNAME} ($(du -h "${LOCAL_ISO}" | cut -f1)) to ${STORAGE} — this can take a while..."
UPID=$(pve POST "/nodes/${PVE_NODE}/storage/${STORAGE}/upload" \
    --max-time 7200 -F "content=iso" -F "filename=@${LOCAL_ISO}" | jq -r '.data')
[[ -n "${UPID}" && "${UPID}" != "null" ]] || fail "Upload did not return a task ID"
while :; do
    sleep 5
    ST=$(pve GET "/nodes/${PVE_NODE}/tasks/${UPID}/status")
    [[ "$(echo "${ST}" | jq -r '.data.status')" == "stopped" ]] || continue
    [[ "$(echo "${ST}" | jq -r '.data.exitstatus')" == "OK" ]] || fail "Upload task failed: $(echo "${ST}" | jq -r '.data.exitstatus')"
    break
done
log "Upload complete."
echo "${STORAGE}:iso/${FNAME}"
