#!/usr/bin/env bash
# =============================================================================
# Clone a VM from a Proxmox Template
# =============================================================================
# Description : Clones an existing Proxmox VM template into a new virtual
#               machine. Templates let you create new VMs in seconds rather
#               than going through a full OS installation each time.
#               After cloning, cloud-init configuration is optionally updated
#               with a new hostname, IP, and SSH key.
#
# Prerequisites:
#   - A Proxmox template must already exist (convert a VM with: qm template <vmid>)
#   - Run as root on the Proxmox VE host
#
# What is a Template?
#   A Proxmox template is a "master copy" of a VM that you can clone
#   as many times as you need. Think of it like a gold master image.
#   Once you have a good baseline Ubuntu or Windows VM, you convert it
#   to a template and then clone from it for every new server you need.
#   This is the same concept as AWS AMIs or Azure Managed Images.
#
# Usage:
#   chmod +x clone-vm-from-template.sh
#   ./clone-vm-from-template.sh [OPTIONS]
#
# Options:
#   -t, --template-id  Source template VM ID (required)
#   -i, --vmid         New VM ID (required)
#   -n, --name         New VM hostname (required)
#   -s, --storage      Target storage pool (default: same as template)
#   -m, --memory       Override RAM in MB (optional)
#   -c, --cores        Override CPU cores (optional)
#   -k, --ssh-key      Path to SSH public key to inject (optional)
#   -p, --ip           Static IP in CIDR format e.g. 192.168.1.50/24 (optional, default: dhcp)
#   -g, --gateway      Gateway IP (required if using static IP)
#   -h, --help         Show this help
#
# Examples:
#   # Clone Ubuntu template (ID 9000) to new VM ID 101
#   ./clone-vm-from-template.sh -t 9000 -i 101 -n "web01"
#
#   # Clone with static IP
#   ./clone-vm-from-template.sh -t 9000 -i 102 -n "db01" -p 192.168.1.52/24 -g 192.168.1.1
#
#   # Clone with more resources than the template
#   ./clone-vm-from-template.sh -t 9000 -i 103 -n "monitor01" -m 8192 -c 4
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

TEMPLATE_ID=""; NEW_VMID=""; VM_NAME=""; STORAGE=""
MEMORY=""; CORES=""; SSH_KEY_PATH=""; IP_CONFIG="ip=dhcp"; GATEWAY=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -t|--template-id) TEMPLATE_ID="$2"; shift 2 ;;
    -i|--vmid)        NEW_VMID="$2"; shift 2 ;;
    -n|--name)        VM_NAME="$2"; shift 2 ;;
    -s|--storage)     STORAGE="$2"; shift 2 ;;
    -m|--memory)      MEMORY="$2"; shift 2 ;;
    -c|--cores)       CORES="$2"; shift 2 ;;
    -k|--ssh-key)     SSH_KEY_PATH="$2"; shift 2 ;;
    -p|--ip)          IP_CONFIG="ip=$2"; shift 2 ;;
    -g|--gateway)     GATEWAY=",gw=$2"; shift 2 ;;
    -h|--help)
      sed -n '/^# Usage/,/^# Author/p' "$0" | grep '^#' | sed 's/^# \?//'; exit 0 ;;
    *) error "Unknown option: $1" ;;
  esac
done

[[ $(id -u) -eq 0 ]]   || error "Must run as root on the Proxmox host."
[[ -n "$TEMPLATE_ID" ]] || error "--template-id is required."
[[ -n "$NEW_VMID" ]]    || error "--vmid is required."
[[ -n "$VM_NAME" ]]     || error "--name is required."

qm status "$TEMPLATE_ID" &>/dev/null || error "Template ID $TEMPLATE_ID does not exist."
qm status "$NEW_VMID"    &>/dev/null && error "VM ID $NEW_VMID already in use. Choose another with --vmid."

section "Cloning template $TEMPLATE_ID → VM $NEW_VMID ($VM_NAME)"
CLONE_ARGS="$TEMPLATE_ID $NEW_VMID --name $VM_NAME --full"
[[ -n "$STORAGE" ]] && CLONE_ARGS="$CLONE_ARGS --storage $STORAGE"
qm clone $CLONE_ARGS
log "Clone complete."

section "Configuring new VM"
[[ -n "$MEMORY" ]] && { qm set "$NEW_VMID" --memory "$MEMORY"; log "Memory set to ${MEMORY}MB."; }
[[ -n "$CORES"  ]] && { qm set "$NEW_VMID" --cores "$CORES";   log "Cores set to $CORES."; }

# Update cloud-init settings
qm set "$NEW_VMID" --ipconfig0 "${IP_CONFIG}${GATEWAY}"
qm set "$NEW_VMID" --hostname "$VM_NAME" 2>/dev/null || true

if [[ -n "$SSH_KEY_PATH" ]]; then
  [[ -f "$SSH_KEY_PATH" ]] || error "SSH key not found at $SSH_KEY_PATH"
  qm set "$NEW_VMID" --sshkeys "$SSH_KEY_PATH"
  log "SSH key injected."
fi

section "Starting VM"
qm start "$NEW_VMID"
log "VM $NEW_VMID ($VM_NAME) started successfully."

section "Done"
echo -e "${BOLD}New VM Details:${NC}"
echo "  VM ID : $NEW_VMID"
echo "  Name  : $VM_NAME"
echo "  IP    : ${IP_CONFIG}${GATEWAY}"
echo ""
echo "Wait ~30 seconds for cloud-init, then connect:"
[[ "$IP_CONFIG" == "ip=dhcp" ]] && \
  echo "  Find IP in Proxmox UI → VM $NEW_VMID → Summary" || \
  echo -e "  ${CYAN}ssh sysadmin@$(echo $IP_CONFIG | grep -oP '[\d.]+(?=/)' || echo '<ip>')${NC}"
