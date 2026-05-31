#!/usr/bin/env bash
# =============================================================================
# Extend LVM Disk — Ubuntu
# Extends an LVM logical volume to consume all available unallocated space
# on its physical disk. Dynamically detects the OS disk, last partition,
# volume group, and logical volume — no hardcoded device paths.
#
# Workflow:
#   1. Detect the root disk (the disk containing the root filesystem)
#   2. Identify the last partition on that disk
#   3. Grow the partition using growpart
#   4. Resize the LVM physical volume (pvresize)
#   5. Extend the logical volume to use all free space (lvextend)
#   6. Resize the filesystem (resize2fs / xfs_growfs)
#
# Prerequisites:
#   - cloud-guest-utils (provides growpart)
#   - lvm2
#
# Usage:
#   sudo ./extend-disks.sh
#   sudo ./extend-disks.sh --disk /dev/sda --partition 3
#
# Options:
#   --disk <device>       Override disk device (e.g. /dev/sda). Auto-detected by default.
#   --partition <num>     Override partition number. Auto-detected by default.
#
# Author:            Darren Pilkington
# Version:           1.1
# Date:              31-05-2026
# =============================================================================

set -euo pipefail

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/storage-management"
LOG_FILE="${LOG_DIR}/extend-disks-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── Argument parsing ────────────────────────────────────────────────────────
DISK_OVERRIDE=""
PART_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --disk)      DISK_OVERRIDE="$2";  shift 2 ;;
        --partition) PART_OVERRIDE="$2";  shift 2 ;;
        --help)
            grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,2\}//'
            exit 0
            ;;
        *) fail "Unknown argument: $1. Use --help for usage." ;;
    esac
done

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || fail "Run as root: sudo ./extend-disks.sh"

for cmd in growpart pvresize lvextend lsblk pvs lvdisplay; do
    command -v "${cmd}" &>/dev/null || fail "Required tool '${cmd}' not found. Install: apt-get install -y cloud-guest-utils lvm2"
done

log "LVM disk extension starting on $(hostname -f 2>/dev/null || hostname)"
log "Log file: ${LOG_FILE}"

# ─── Detect root disk ────────────────────────────────────────────────────────
if [[ -n "${DISK_OVERRIDE}" ]]; then
    ROOT_DISK="${DISK_OVERRIDE}"
    log "Using specified disk: ${ROOT_DISK}"
else
    log "Auto-detecting root disk..."
    # Find the disk that owns the partition mounted at /
    ROOT_PART=$(findmnt -n -o SOURCE / | sed 's/\[.*//')
    # Strip partition number to get the base disk (handles /dev/sda1, /dev/nvme0n1p1, etc.)
    if [[ "${ROOT_PART}" =~ (nvme[0-9]+n[0-9]+)p[0-9]+$ ]]; then
        ROOT_DISK="/dev/${BASH_REMATCH[1]}"
    elif [[ "${ROOT_PART}" =~ ([a-z]+)[0-9]+$ ]]; then
        ROOT_DISK="/dev/${BASH_REMATCH[1]}"
    else
        fail "Could not determine base disk from '${ROOT_PART}'. Use --disk to specify."
    fi
    log "Root disk detected: ${ROOT_DISK}"
fi

[[ -b "${ROOT_DISK}" ]] || fail "Disk device '${ROOT_DISK}' not found."

# ─── Detect last partition ───────────────────────────────────────────────────
if [[ -n "${PART_OVERRIDE}" ]]; then
    PART_NUM="${PART_OVERRIDE}"
    log "Using specified partition number: ${PART_NUM}"
else
    log "Detecting last partition on ${ROOT_DISK}..."
    PART_NUM=$(lsblk -no PARTN "${ROOT_DISK}" 2>/dev/null | grep -v "^$" | tail -1)
    [[ -n "${PART_NUM}" ]] || fail "Could not detect partitions on ${ROOT_DISK}."
    log "Last partition number: ${PART_NUM}"
fi

# Build full partition device path (handles both /dev/sdaN and /dev/nvme0n1pN)
if [[ "${ROOT_DISK}" =~ nvme ]]; then
    PARTITION="${ROOT_DISK}p${PART_NUM}"
else
    PARTITION="${ROOT_DISK}${PART_NUM}"
fi

[[ -b "${PARTITION}" ]] || fail "Partition '${PARTITION}' not found."
log "Target partition: ${PARTITION}"

# ─── Show disk layout before ─────────────────────────────────────────────────
log "Disk layout before extension:"
lsblk "${ROOT_DISK}" 2>&1 | tee -a "${LOG_FILE}"

# ─── Step 1: Grow the partition ──────────────────────────────────────────────
log "Step 1/4: Extending partition ${PARTITION} with growpart..."
growpart "${ROOT_DISK}" "${PART_NUM}" 2>&1 | tee -a "${LOG_FILE}" \
    || fail "growpart failed. Disk may have no unallocated space."
log "Partition extended."

# ─── Step 2: Notify kernel of partition change ───────────────────────────────
log "Step 2/4: Refreshing kernel partition table..."
partprobe "${ROOT_DISK}" 2>&1 | tee -a "${LOG_FILE}" || true

# ─── Step 3: Resize LVM physical volume ─────────────────────────────────────
log "Step 3/4: Resizing LVM physical volume on ${PARTITION}..."
pvresize "${PARTITION}" 2>&1 | tee -a "${LOG_FILE}"
log "Physical volume resized."

# ─── Detect volume group and logical volume ───────────────────────────────────
VG_NAME=$(pvs --noheadings -o vg_name "${PARTITION}" 2>/dev/null | tr -d ' ')
[[ -n "${VG_NAME}" ]] || fail "No LVM volume group found on ${PARTITION}."
log "Volume group: ${VG_NAME}"

LV_PATH=$(lvdisplay -C -o lv_path --noheadings "${VG_NAME}" 2>/dev/null | tr -d ' ' | head -1)
[[ -n "${LV_PATH}" ]] || fail "No logical volume found in VG '${VG_NAME}'."
log "Logical volume: ${LV_PATH}"

# ─── Step 4: Extend logical volume and resize filesystem ─────────────────────
log "Step 4/4: Extending logical volume ${LV_PATH} to use all free space..."
lvextend -l +100%FREE "${LV_PATH}" 2>&1 | tee -a "${LOG_FILE}"
log "Logical volume extended."

log "Resizing filesystem on ${LV_PATH}..."
FS_TYPE=$(lsblk -no FSTYPE "${LV_PATH}" 2>/dev/null | head -1)
case "${FS_TYPE}" in
    ext2|ext3|ext4)
        resize2fs "${LV_PATH}" 2>&1 | tee -a "${LOG_FILE}"
        log "ext filesystem resized (resize2fs)."
        ;;
    xfs)
        xfs_growfs "${LV_PATH}" 2>&1 | tee -a "${LOG_FILE}"
        log "XFS filesystem resized (xfs_growfs)."
        ;;
    *)
        warn "Unknown filesystem type '${FS_TYPE}'. Manual filesystem resize may be required."
        ;;
esac

# ─── Show disk layout after ──────────────────────────────────────────────────
log "Disk layout after extension:"
lsblk "${ROOT_DISK}" 2>&1 | tee -a "${LOG_FILE}"
df -h / 2>&1 | tee -a "${LOG_FILE}"

log "Disk extension complete. Log: ${LOG_FILE}"
