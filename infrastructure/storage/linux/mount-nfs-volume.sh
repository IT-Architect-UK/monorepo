#!/usr/bin/env bash
# =============================================================================
# Mount NFS Volume — Ubuntu
# Mounts an NFS share on a local mount point and optionally persists the
# mount in /etc/fstab so it survives reboots.
#
# Installs nfs-common if not already present. Tests server connectivity
# before attempting to mount. Uses NFSv4 by default.
#
# Usage:
#   sudo ./mount-nfs-volume.sh --server 192.168.1.100 --export /data --mount /mnt/nfs
#   sudo ./mount-nfs-volume.sh --server nas.corp.local --export /backups --mount /mnt/backups --nfs-version 3
#   sudo ./mount-nfs-volume.sh --server 192.168.1.100 --export /data --mount /mnt/nfs --no-fstab
#
# Options:
#   --server <host/ip>    NFS server hostname or IP (required)
#   --export <path>       NFS export path on the server (required)
#   --mount <path>        Local directory to mount to (required)
#   --nfs-version <n>     NFS version: 3 or 4 (default: 4)
#   --no-fstab            Skip adding the mount to /etc/fstab
#
# Author:            Darren Pilkington
# Version:           1.1
# Date:              31-05-2026
# =============================================================================

set -euo pipefail

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/storage-management"
LOG_FILE="${LOG_DIR}/mount-nfs-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── Argument parsing ────────────────────────────────────────────────────────
NFS_SERVER=""
NFS_EXPORT=""
MOUNT_POINT=""
NFS_VERSION="4"
ADD_FSTAB=true

while [[ $# -gt 0 ]]; do
    case "$1" in
        --server)      NFS_SERVER="$2";   shift 2 ;;
        --export)      NFS_EXPORT="$2";   shift 2 ;;
        --mount)       MOUNT_POINT="$2";  shift 2 ;;
        --nfs-version) NFS_VERSION="$2";  shift 2 ;;
        --no-fstab)    ADD_FSTAB=false;   shift   ;;
        --help)
            grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,2\}//'
            exit 0
            ;;
        *) fail "Unknown argument: $1. Use --help for usage." ;;
    esac
done

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]]      || fail "Run as root: sudo ./mount-nfs-volume.sh"
[[ -n "${NFS_SERVER}" ]]   || fail "--server is required."
[[ -n "${NFS_EXPORT}" ]]   || fail "--export is required."
[[ -n "${MOUNT_POINT}" ]]  || fail "--mount is required."
[[ "${NFS_EXPORT}" == /* ]] || fail "--export must be an absolute path starting with /"
[[ "${MOUNT_POINT}" == /* ]] || fail "--mount must be an absolute path starting with /"
[[ "${NFS_VERSION}" == "3" || "${NFS_VERSION}" == "4" ]] \
    || fail "--nfs-version must be 3 or 4."

log "Mounting NFS volume on $(hostname -f 2>/dev/null || hostname)"
log "  Server      : ${NFS_SERVER}"
log "  Export      : ${NFS_EXPORT}"
log "  Mount point : ${MOUNT_POINT}"
log "  NFS version : ${NFS_VERSION}"
log "  fstab entry : ${ADD_FSTAB}"
log "Log file: ${LOG_FILE}"

# ─── Install nfs-common ──────────────────────────────────────────────────────
if ! dpkg -l nfs-common 2>/dev/null | grep -q "^ii"; then
    log "Installing nfs-common..."
    apt-get update -y 2>&1 | tee -a "${LOG_FILE}"
    apt-get install -y nfs-common 2>&1 | tee -a "${LOG_FILE}"
    log "nfs-common installed."
else
    log "nfs-common already installed."
fi

# ─── Test server connectivity ─────────────────────────────────────────────────
log "Testing connectivity to NFS server ${NFS_SERVER}..."
if ping -c 2 -W 3 "${NFS_SERVER}" &>/dev/null; then
    log "NFS server is reachable."
else
    warn "Cannot ping ${NFS_SERVER}. Attempting mount anyway — server may not respond to ICMP."
fi

# ─── Create mount point ───────────────────────────────────────────────────────
if [[ ! -d "${MOUNT_POINT}" ]]; then
    log "Creating mount point: ${MOUNT_POINT}..."
    mkdir -p "${MOUNT_POINT}"
    log "Mount point created."
else
    log "Mount point already exists: ${MOUNT_POINT}"
fi

# ─── Check if already mounted ─────────────────────────────────────────────────
if mountpoint -q "${MOUNT_POINT}" 2>/dev/null; then
    warn "${MOUNT_POINT} is already mounted. Skipping mount."
else
    # ─── Mount the NFS share ──────────────────────────────────────────────────
    log "Mounting ${NFS_SERVER}:${NFS_EXPORT} at ${MOUNT_POINT} (NFS v${NFS_VERSION})..."
    mount -t nfs -o "rw,nfsvers=${NFS_VERSION},hard,timeo=600,retrans=2" \
        "${NFS_SERVER}:${NFS_EXPORT}" "${MOUNT_POINT}" \
        2>&1 | tee -a "${LOG_FILE}"

    mountpoint -q "${MOUNT_POINT}" || fail "Mount verification failed. Check server exports and firewall rules."
    log "NFS share mounted successfully at ${MOUNT_POINT}."
fi

# ─── Add to fstab for persistence ────────────────────────────────────────────
if [[ "${ADD_FSTAB}" == true ]]; then
    FSTAB_ENTRY="${NFS_SERVER}:${NFS_EXPORT}  ${MOUNT_POINT}  nfs  rw,nfsvers=${NFS_VERSION},hard,timeo=600,retrans=2,_netdev  0  0"

    if grep -qF "${NFS_SERVER}:${NFS_EXPORT}" /etc/fstab 2>/dev/null; then
        warn "fstab already contains an entry for ${NFS_SERVER}:${NFS_EXPORT} — skipping."
    else
        log "Adding mount to /etc/fstab for persistence across reboots..."
        cp /etc/fstab "/etc/fstab.bak.$(date '+%Y%m%d-%H%M%S')"
        echo "${FSTAB_ENTRY}" >> /etc/fstab
        log "fstab entry added."
        log "  ${FSTAB_ENTRY}"
    fi
fi

log "NFS mount complete. Log: ${LOG_FILE}"
df -h "${MOUNT_POINT}" 2>&1 | tee -a "${LOG_FILE}"
