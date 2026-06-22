#!/usr/bin/env bash
# =============================================================================
# Deploy Ubuntu 24.04 LXC Container on Proxmox VE
# =============================================================================
# Description : Creates a lightweight Ubuntu 24.04 LTS LXC container on
#               Proxmox VE. LXC containers share the host kernel, making
#               them significantly lighter than full VMs — perfect for
#               running services like DNS, monitoring agents, web servers,
#               or any Linux workload that does not need Windows or a custom
#               kernel.
#
# LXC vs VM — When to use which:
#   Use LXC when:
#     • You need a Linux-only service (web server, database, DNS, monitoring)
#     • You want maximum density on your homelab host
#     • Boot times and resource usage matter
#     • You do not need nested virtualisation or custom kernel modules
#   Use a full VM when:
#     • You need Windows
#     • You need to run Docker or Kubernetes inside the guest
#     • You need custom kernel modules (e.g. WireGuard on older kernels)
#     • You need complete OS isolation
#
# Prerequisites:
#   - Proxmox VE 8.x host (run as root on the PVE host)
#   - Ubuntu 24.04 LXC template (downloaded automatically if missing)
#
# Usage:
#   chmod +x deploy-ubuntu-lxc.sh
#   ./deploy-ubuntu-lxc.sh [OPTIONS]
#
# Options:
#   -i, --ctid       Container ID (default: 300)
#   -n, --name       Hostname (default: ubuntu-lxc)
#   -m, --memory     RAM in MB (default: 512)
#   -c, --cores      CPU cores (default: 1)
#   -d, --disk       Root disk in GB (default: 8)
#   -s, --storage    Storage pool (default: local-lvm)
#   -b, --bridge     Network bridge (default: vmbr0)
#   -p, --password   Root password (default: prompted)
#   -u, --unprivileged  Run as unprivileged (default: yes — recommended)
#   -h, --help       Show this help
#
# Examples:
#   ./deploy-ubuntu-lxc.sh -i 301 -n "pihole" -m 256
#   ./deploy-ubuntu-lxc.sh -i 302 -n "monitoring" -m 1024 -d 20
#
# Author  : IT-Architect-UK  |  https://github.com/IT-Architect-UK/monorepo
# Updated : 2026-06
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; CYAN='\033[0;36m'; NC='\033[0m'

log()     { echo -e "${GREEN}[✔]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✘] ERROR:${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BLUE}${BOLD}━━━ $* ━━━${NC}"; }

CTID=300; CT_NAME="ubuntu-lxc"; MEMORY=512; CORES=1
DISK_SIZE=8; STORAGE="local-lvm"; BRIDGE="vmbr0"
CT_PASSWORD=""; UNPRIVILEGED=1

while [[ $# -gt 0 ]]; do
  case $1 in
    -i|--ctid)          CTID="$2"; shift 2 ;;
    -n|--name)          CT_NAME="$2"; shift 2 ;;
    -m|--memory)        MEMORY="$2"; shift 2 ;;
    -c|--cores)         CORES="$2"; shift 2 ;;
    -d|--disk)          DISK_SIZE="$2"; shift 2 ;;
    -s|--storage)       STORAGE="$2"; shift 2 ;;
    -b|--bridge)        BRIDGE="$2"; shift 2 ;;
    -p|--password)      CT_PASSWORD="$2"; shift 2 ;;
    -u|--unprivileged)  UNPRIVILEGED="$2"; shift 2 ;;
    -h|--help)
      sed -n '/^# Usage/,/^# Author/p' "$0" | grep '^#' | sed 's/^# \?//'; exit 0 ;;
    *) error "Unknown option: $1" ;;
  esac
done

[[ $(id -u) -eq 0 ]] || error "Must run as root."
pct status "$CTID" &>/dev/null && error "Container ID $CTID already exists."

[[ -z "$CT_PASSWORD" ]] && { read -rsp "Enter root password for container: " CT_PASSWORD; echo; }

section "Checking for Ubuntu 24.04 LXC template"
TEMPLATE=$(pveam list local 2>/dev/null | grep -i "ubuntu-24.04" | awk '{print $1}' | head -1 || true)
if [[ -z "$TEMPLATE" ]]; then
  log "Downloading Ubuntu 24.04 LXC template..."
  pveam update
  AVAIL=$(pveam available --section system | grep "ubuntu-24.04" | awk '{print $2}' | head -1)
  [[ -n "$AVAIL" ]] || error "Ubuntu 24.04 template not available. Run: pveam update"
  pveam download local "$AVAIL"
  TEMPLATE="local:vztmpl/${AVAIL}"
  log "Template downloaded: $TEMPLATE"
else
  log "Template found: $TEMPLATE"
fi

section "Creating container $CTID ($CT_NAME)"
pct create "$CTID" "$TEMPLATE" \
  --hostname "$CT_NAME" \
  --password "$CT_PASSWORD" \
  --memory "$MEMORY" \
  --cores "$CORES" \
  --rootfs "${STORAGE}:${DISK_SIZE}" \
  --net0 "name=eth0,bridge=${BRIDGE},ip=dhcp" \
  --features "nesting=1" \
  --unprivileged "$UNPRIVILEGED" \
  --start 1

log "Container created and started."
sleep 5

section "Deployment complete"
IP=$(pct exec "$CTID" -- hostname -I 2>/dev/null | awk '{print $1}' || echo "")
echo -e "${BOLD}Container Details:${NC}"
echo "  CT ID    : $CTID"
echo "  Hostname : $CT_NAME"
echo "  Memory   : ${MEMORY}MB"
[[ -n "$IP" ]] && echo -e "  IP Addr  : ${CYAN}$IP${NC}"
echo ""
echo "Connect to the container:"
echo "  pct enter $CTID              (direct console access)"
[[ -n "$IP" ]] && echo -e "  ${CYAN}ssh root@$IP${NC}  (SSH — enable first with: pct exec $CTID -- systemctl enable --now ssh)"
