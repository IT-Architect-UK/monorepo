#!/usr/bin/env bash
# =============================================================================
# Deploy Ubuntu 24.04 LTS VM on Proxmox VE using Cloud-Init
# =============================================================================
# Description : Creates a new Ubuntu 24.04 LTS virtual machine on Proxmox VE
#               using a cloud-init template. Cloud-init automatically sets the
#               hostname, SSH key, user, and network on first boot — no manual
#               installation wizard required. This is the fastest way to spin
#               up a ready-to-use Ubuntu server in under 60 seconds.
#
# Prerequisites:
#   - Proxmox VE 8.x host (run this script directly on the PVE host as root)
#   - Ubuntu 24.04 cloud image downloaded (script can do this automatically)
#   - An SSH public key to inject (for passwordless login)
#
# What is Cloud-Init?
#   Cloud-init is a standard tool used by cloud providers (AWS, Azure, GCP)
#   to automatically configure virtual machines on first boot. Instead of
#   going through an installation wizard, you provide configuration (username,
#   SSH key, network settings) and the VM configures itself automatically.
#   This is exactly how AWS EC2 instances work when you launch them.
#
# Usage:
#   chmod +x deploy-ubuntu-2404.sh
#   ./deploy-ubuntu-2404.sh [OPTIONS]
#
# Options:
#   -i, --vmid       VM ID number (default: 100)
#   -n, --name       VM hostname (default: ubuntu-2404)
#   -m, --memory     RAM in MB (default: 2048)
#   -c, --cores      CPU cores (default: 2)
#   -d, --disk       Disk size to expand to in GB (default: 20)
#   -s, --storage    Proxmox storage pool (default: local-lvm)
#   -b, --bridge     Network bridge (default: vmbr0)
#   -u, --user       Linux username to create (default: sysadmin)
#   -k, --ssh-key    Path to SSH public key file (default: ~/.ssh/id_rsa.pub)
#   -p, --password   User password (default: prompted)
#   -h, --help       Show this help
#
# Examples:
#   # Quick deploy with all defaults (uses your default SSH key)
#   ./deploy-ubuntu-2404.sh
#
#   # Deploy a web server VM with a specific ID and name
#   ./deploy-ubuntu-2404.sh -i 110 -n "web01" -m 4096 -d 40
#
#   # Deploy monitoring server with custom user
#   ./deploy-ubuntu-2404.sh -i 111 -n "monitor01" -u "admin" -k ~/.ssh/homelab.pub
#
# After the VM is created:
#   1. Start the VM: qm start <vmid>
#   2. Wait ~30 seconds for cloud-init to complete
#   3. SSH in: ssh <user>@<ip-address>
#      (Find the IP in the Proxmox web UI under the VM's Summary tab)
#
# Author  : IT-Architect-UK  |  https://github.com/IT-Architect-UK/monorepo
# Updated : 2026-06
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${GREEN}[✔]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✘] ERROR:${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BLUE}${BOLD}━━━ $* ━━━${NC}"; }

# ── Defaults ─────────────────────────────────────────────────────────────────
VMID=100
VM_NAME="ubuntu-2404"
MEMORY=2048
CORES=2
DISK_SIZE=20
STORAGE="local-lvm"
BRIDGE="vmbr0"
CI_USER="sysadmin"
SSH_KEY_PATH="${HOME}/.ssh/id_rsa.pub"
CI_PASSWORD=""
CLOUD_IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
IMAGE_NAME="noble-server-cloudimg-amd64.img"
IMAGE_DIR="/var/lib/vz/template/iso"

while [[ $# -gt 0 ]]; do
  case $1 in
    -i|--vmid)      VMID="$2"; shift 2 ;;
    -n|--name)      VM_NAME="$2"; shift 2 ;;
    -m|--memory)    MEMORY="$2"; shift 2 ;;
    -c|--cores)     CORES="$2"; shift 2 ;;
    -d|--disk)      DISK_SIZE="$2"; shift 2 ;;
    -s|--storage)   STORAGE="$2"; shift 2 ;;
    -b|--bridge)    BRIDGE="$2"; shift 2 ;;
    -u|--user)      CI_USER="$2"; shift 2 ;;
    -k|--ssh-key)   SSH_KEY_PATH="$2"; shift 2 ;;
    -p|--password)  CI_PASSWORD="$2"; shift 2 ;;
    -h|--help)
      sed -n '/^# Usage/,/^# Author/p' "$0" | grep '^#' | sed 's/^# \?//'; exit 0 ;;
    *) error "Unknown option: $1" ;;
  esac
done

section "Pre-flight checks"
[[ $(id -u) -eq 0 ]] || error "Must run as root on the Proxmox host."
command -v qm &>/dev/null || error "'qm' not found — run on the Proxmox VE host."
qm status "$VMID" &>/dev/null && error "VM ID $VMID already exists. Use --vmid to choose another."

[[ -f "$SSH_KEY_PATH" ]] || error "SSH public key not found at $SSH_KEY_PATH. Generate one with: ssh-keygen -t ed25519"
SSH_KEY=$(cat "$SSH_KEY_PATH")

if [[ -z "$CI_PASSWORD" ]]; then
  read -rsp "Enter password for user '$CI_USER': " CI_PASSWORD; echo
fi

section "Downloading Ubuntu 24.04 cloud image"
if [[ ! -f "${IMAGE_DIR}/${IMAGE_NAME}" ]]; then
  log "Downloading Ubuntu 24.04 LTS cloud image (~600 MB)..."
  wget -q --show-progress -O "${IMAGE_DIR}/${IMAGE_NAME}" "$CLOUD_IMAGE_URL"
  log "Download complete."
else
  log "Cloud image already present, skipping download."
fi

section "Creating VM $VMID ($VM_NAME)"
qm create "$VMID" \
  --name "$VM_NAME" \
  --memory "$MEMORY" \
  --cores "$CORES" \
  --cpu "host" \
  --machine "q35" \
  --net0 "virtio,bridge=${BRIDGE}" \
  --scsihw "virtio-scsi-pci" \
  --serial0 socket --vga serial0 \
  --ostype "l26" \
  --agent "enabled=1" \
  --boot "order=scsi0"

log "Importing cloud image as VM disk..."
qm importdisk "$VMID" "${IMAGE_DIR}/${IMAGE_NAME}" "$STORAGE" --format qcow2

# Attach the imported disk as scsi0
qm set "$VMID" --scsi0 "${STORAGE}:vm-${VMID}-disk-0,cache=writeback,discard=on"

# Add a small cloud-init drive (required for cloud-init to work)
qm set "$VMID" --ide2 "${STORAGE}:cloudinit"

# Resize disk to requested size
log "Expanding disk to ${DISK_SIZE}GB..."
qm resize "$VMID" scsi0 "${DISK_SIZE}G"

section "Configuring Cloud-Init"
qm set "$VMID" \
  --ciuser "$CI_USER" \
  --cipassword "$CI_PASSWORD" \
  --sshkeys <(echo "$SSH_KEY") \
  --ipconfig0 "ip=dhcp" \
  --nameserver "8.8.8.8 8.8.4.4" \
  --searchdomain "local"

log "Cloud-init configured. VM will auto-configure on first boot."

section "Starting VM"
qm start "$VMID"
log "VM started. Waiting for cloud-init to complete (~30 seconds)..."
sleep 35

# Try to get the IP address from the guest agent
IP=$(qm guest cmd "$VMID" network-get-interfaces 2>/dev/null | \
  python3 -c "import json,sys; ifaces=json.load(sys.stdin); \
  [print(a['ip-address']) for i in ifaces for a in i.get('ip-addresses',[]) \
  if a['ip-address-type']=='ipv4' and not a['ip-address'].startswith('127')]" \
  2>/dev/null | head -1 || echo "")

section "Deployment complete"
echo -e "${BOLD}VM Details:${NC}"
echo "  VM ID    : $VMID"
echo "  Name     : $VM_NAME"
echo "  Username : $CI_USER"
[[ -n "$IP" ]] && echo -e "  IP Addr  : ${CYAN}$IP${NC}"
echo ""
echo -e "${BOLD}Connect via SSH:${NC}"
[[ -n "$IP" ]] && echo -e "  ${CYAN}ssh ${CI_USER}@${IP}${NC}" || \
  echo "  Find IP in Proxmox UI → VM $VMID → Summary → then: ssh ${CI_USER}@<ip>"
echo ""
echo "Next steps:"
echo "  1. SSH into the VM and run the server-baseline script"
echo "  2. Install required software (Docker, monitoring agent, etc.)"
echo "  3. Consider converting this VM to a template for fast cloning"
