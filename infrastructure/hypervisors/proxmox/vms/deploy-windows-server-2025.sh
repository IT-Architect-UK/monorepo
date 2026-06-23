#!/usr/bin/env bash
# =============================================================================
# Deploy Windows Server 2025 VM on Proxmox VE
# =============================================================================
# Description : Creates a new Windows Server 2025 virtual machine on a
#               Proxmox VE host using the qm CLI. Configures CPU, memory,
#               storage, and attaches both the Windows ISO and the VirtIO
#               drivers ISO needed for disk and network during installation.
#
# Prerequisites:
#   - Proxmox VE 8.x host (run this script directly on the PVE host as root)
#   - Windows Server 2025 ISO uploaded to Proxmox storage
#   - VirtIO Drivers ISO uploaded to Proxmox storage
#     Download from: https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
#   - At least 60 GB of free storage space
#
# Usage:
#   chmod +x deploy-windows-server-2025.sh
#   ./deploy-windows-server-2025.sh [OPTIONS]
#
# Options:
#   -i, --vmid        VM ID number (default: 200)
#   -n, --name        VM hostname/name (default: win-server-2025)
#   -m, --memory      RAM in MB (default: 4096 = 4 GB)
#   -c, --cores       CPU cores (default: 2)
#   -d, --disk        OS disk size in GB (default: 60)
#   -s, --storage     Proxmox storage pool name (default: local-lvm)
#   -b, --bridge      Network bridge (default: vmbr0)
#   -w, --win-iso     Full path to Windows ISO on storage (default: auto-detect)
#   -v, --virtio-iso  Full path to VirtIO ISO on storage (default: auto-detect)
#   -h, --help        Show this help
#
# Examples:
#   # Basic deployment with defaults
#   ./deploy-windows-server-2025.sh
#
#   # Domain controller with more resources
#   ./deploy-windows-server-2025.sh -i 201 -n "dc01" -m 8192 -c 4 -d 100
#
#   # Specify custom storage pool
#   ./deploy-windows-server-2025.sh -i 202 -n "sql01" -m 16384 -c 8 -s ceph-pool
#
# After the VM is created:
#   1. Open the Proxmox web UI > select the VM > Console
#   2. Start the VM and press any key to boot from the ISO
#   3. During installation when asked for a disk: click "Load driver"
#      and browse to the VirtIO CD > viostor > w11 (or amd64) > OK
#   4. Your disk will now appear — select it and continue installation
#   5. After first boot install remaining VirtIO drivers:
#      Run the virtio-win-guest-tools.exe from the VirtIO CD
#
# Author  : IT-Architect-UK  |  https://github.com/IT-Architect-UK/monorepo
# Updated : 2026-06
# =============================================================================

set -euo pipefail

# ── Colour output helpers ────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[✔]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✘] ERROR:${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BLUE}${BOLD}━━━ $* ━━━${NC}"; }

# ── Load defaults from .env if present ───────────────────────────────────────
ENV_FILE="$(dirname "$0")/../.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE" && log "Loaded defaults from .env"


# ── Default values ───────────────────────────────────────────────────────────
VMID=200
VM_NAME="win-server-2025"
MEMORY="${DEFAULT_MEMORY_MB:-4096}"
CORES="${DEFAULT_CORES:-2}"
DISK_SIZE="${DEFAULT_DISK_GB:-60}"
STORAGE="${PROXMOX_STORAGE:-local-lvm}"
BRIDGE="${PROXMOX_BRIDGE:-vmbr0}"
WIN_ISO=""
VIRTIO_ISO=""

# ── Parse arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    -i|--vmid)        VMID="$2"; shift 2 ;;
    -n|--name)        VM_NAME="$2"; shift 2 ;;
    -m|--memory)      MEMORY="$2"; shift 2 ;;
    -c|--cores)       CORES="$2"; shift 2 ;;
    -d|--disk)        DISK_SIZE="$2"; shift 2 ;;
    -s|--storage)     STORAGE="$2"; shift 2 ;;
    -b|--bridge)      BRIDGE="$2"; shift 2 ;;
    -w|--win-iso)     WIN_ISO="$2"; shift 2 ;;
    -v|--virtio-iso)  VIRTIO_ISO="$2"; shift 2 ;;
    -h|--help)
      sed -n '/^# Usage/,/^# Author/p' "$0" | grep '^#' | sed 's/^# \?//'
      exit 0 ;;
    *) error "Unknown option: $1. Use --help for usage." ;;
  esac
done

# ── Pre-flight checks ────────────────────────────────────────────────────────
section "Pre-flight checks"

[[ $(id -u) -eq 0 ]] || error "This script must be run as root on the Proxmox host."
command -v qm &>/dev/null || error "'qm' command not found. Run this script on the Proxmox VE host."

# Check VM ID is not already in use
if qm status "$VMID" &>/dev/null; then
  error "VM ID $VMID is already in use. Choose a different ID with --vmid."
fi

# Auto-detect ISOs if not specified
if [[ -z "$WIN_ISO" ]]; then
  WIN_ISO=$(find /var/lib/vz/template/iso/ /mnt/ -name "*windows*server*2025*" -o \
            -name "*WS2025*" -o -name "*Server2025*" 2>/dev/null | head -1 || true)
  [[ -n "$WIN_ISO" ]] && log "Auto-detected Windows ISO: $WIN_ISO" || \
    error "Windows Server 2025 ISO not found. Upload it to Proxmox storage and specify with --win-iso"
fi

if [[ -z "$VIRTIO_ISO" ]]; then
  VIRTIO_ISO=$(find /var/lib/vz/template/iso/ -name "virtio-win*.iso" 2>/dev/null | head -1 || true)
  [[ -n "$VIRTIO_ISO" ]] && log "Auto-detected VirtIO ISO: $VIRTIO_ISO" || \
    warn "VirtIO ISO not found. VM will be created but you must add it manually."
fi

log "VM ID      : $VMID"
log "VM Name    : $VM_NAME"
log "Memory     : ${MEMORY} MB ($(( MEMORY / 1024 )) GB)"
log "CPU Cores  : $CORES"
log "Disk Size  : ${DISK_SIZE} GB"
log "Storage    : $STORAGE"
log "Network    : $BRIDGE"

# ── Create the VM ────────────────────────────────────────────────────────────
section "Creating VM $VMID ($VM_NAME)"

qm create "$VMID" \
  --name "$VM_NAME" \
  --memory "$MEMORY" \
  --cores "$CORES" \
  --cpu "host" \
  --machine "q35" \
  --bios "ovmf" \
  --efidisk0 "${STORAGE}:1,efitype=4m,pre-enrolled-keys=0" \
  --tpmstate0 "${STORAGE}:1,version=v2.0" \
  --scsihw "virtio-scsi-pci" \
  --scsi0 "${STORAGE}:${DISK_SIZE},cache=writeback,discard=on" \
  --ide2 "${WIN_ISO},media=disk" \
  --net0 "virtio,bridge=${BRIDGE}" \
  --ostype "win11" \
  --tablet 1 \
  --boot "order=ide2;scsi0" \
  --vga "std" \
  --agent "enabled=1"

log "VM created successfully."

# Attach VirtIO drivers ISO on a separate virtual CD drive
if [[ -n "$VIRTIO_ISO" ]]; then
  qm set "$VMID" --ide3 "${VIRTIO_ISO},media=cdrom"
  log "VirtIO drivers ISO attached on ide3."
fi

# ── Summary ──────────────────────────────────────────────────────────────────
section "Deployment complete"
echo -e "${BOLD}Next steps:${NC}"
echo "  1. Open Proxmox web UI → VM $VMID ($VM_NAME) → Console"
echo "  2. Click 'Start' and press any key to boot from the Windows ISO"
echo "  3. At the disk selection screen, click 'Load driver'"
echo "     Browse to: VirtIO CD → viostor → amd64 → OK"
echo "  4. Select the disk and complete the Windows installation"
echo "  5. After first boot, run virtio-win-guest-tools.exe from the VirtIO CD"
echo "  6. Enable Remote Desktop and run the Windows server baseline script"
echo ""
echo -e "  Proxmox UI: ${CYAN}https://$(hostname -I | awk '{print $1}'):8006${NC}"
