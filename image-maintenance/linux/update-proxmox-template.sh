#!/usr/bin/env bash
# =============================================================================
# update-proxmox-template.sh
# =============================================================================
# Updates an existing Ubuntu cloud-init template on Proxmox VE.
#
# Why update templates?
# ──────────────────────
# When you clone a template to create a new VM, that VM starts with whatever
# OS updates were current when the template was created. If the template is
# 3 months old, every new VM starts 3 months behind on patches. By updating
# your template monthly, new VMs start fresh and patched.
#
# What this script does:
#   1. Converts the template back to a regular VM
#   2. Starts the VM
#   3. SSHes in and applies all OS updates
#   4. Cleans cloud-init cache (so clones get a fresh first-boot)
#   5. Shuts the VM down and re-converts to template
#
# Prerequisites:
#   - Run on the Proxmox VE host as root
#   - The template must use cloud-init with a known SSH key
#   - qemu-guest-agent installed in the template
#
# Usage:
#   ./update-proxmox-template.sh --template-id 9000 --ssh-key ~/.ssh/id_rsa
#   ./update-proxmox-template.sh -t 9000 -k ~/.ssh/id_rsa -u ubuntu
#
# Options:
#   -t, --template-id ID    VM/template ID to update (required)
#   -k, --ssh-key PATH      SSH private key to access the VM (required)
#   -u, --ssh-user USER     SSH user (default: ubuntu)
#   -w, --wait-seconds N    Seconds to wait for VM to boot (default: 60)
#
# Author  : IT-Architect-UK
# Repo    : https://github.com/IT-Architect-UK/monorepo
# Version : 1.0.0
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
log()     { echo -e "${GREEN}[✔]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✘] ERROR:${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BLUE}${BOLD}━━━ $* ━━━${NC}"; }

[[ $EUID -ne 0 ]] && error "Run as root on the Proxmox host"

TEMPLATE_ID=""; SSH_KEY=""; SSH_USER="ubuntu"; WAIT_SECONDS=60

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--template-id)  TEMPLATE_ID="$2"; shift 2 ;;
        -k|--ssh-key)      SSH_KEY="$2";      shift 2 ;;
        -u|--ssh-user)     SSH_USER="$2";     shift 2 ;;
        -w|--wait-seconds) WAIT_SECONDS="$2"; shift 2 ;;
        *) error "Unknown option: $1" ;;
    esac
done

[[ -z "$TEMPLATE_ID" ]] && error "Specify --template-id"
[[ -z "$SSH_KEY" ]]     && error "Specify --ssh-key"
[[ ! -f "$SSH_KEY" ]]   && error "SSH key not found: $SSH_KEY"
command -v qm &>/dev/null || error "This script must run on a Proxmox VE host"

section "Proxmox Template Update — VM $TEMPLATE_ID"

section "1 — Convert Template to VM"
# Check if it's currently a template
IS_TEMPLATE=$(qm config "$TEMPLATE_ID" | grep -c "template: 1" || true)
if [[ "$IS_TEMPLATE" -gt 0 ]]; then
    log "Converting template $TEMPLATE_ID back to VM..."
    qm set "$TEMPLATE_ID" --template 0
    log "Converted to regular VM"
else
    warn "VM $TEMPLATE_ID is not a template — proceeding as regular VM"
fi

section "2 — Start VM"
qm start "$TEMPLATE_ID"
log "VM started. Waiting ${WAIT_SECONDS}s for boot..."
sleep "$WAIT_SECONDS"

# Get IP from QEMU guest agent
VM_IP=""
for i in $(seq 1 12); do
    VM_IP=$(qm guest cmd "$TEMPLATE_ID" network-get-interfaces 2>/dev/null | \
        python3 -c "import sys,json; ifaces=json.load(sys.stdin); [print(addr['ip-address']) for iface in ifaces for addr in iface.get('ip-addresses',[]) if addr.get('ip-address-type')=='ipv4' and not addr['ip-address'].startswith('127')]" 2>/dev/null | head -1 || true)
    [[ -n "$VM_IP" ]] && break
    warn "Waiting for IP... (attempt $i/12)"
    sleep 10
done
[[ -z "$VM_IP" ]] && error "Could not get VM IP from guest agent. Check VM has qemu-guest-agent installed."
log "VM IP: $VM_IP"

section "3 — Apply OS Updates"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -i $SSH_KEY"

log "Connecting to $SSH_USER@$VM_IP..."
ssh $SSH_OPTS "$SSH_USER@$VM_IP" << 'REMOTECMDS'
set -euo pipefail
echo "[UPDATE] Refreshing package lists..."
sudo apt-get update -q

echo "[UPDATE] Applying upgrades..."
sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"

echo "[UPDATE] Removing unused packages..."
sudo apt-get autoremove -y && sudo apt-get clean

echo "[CLEAN] Clearing cloud-init cache..."
sudo cloud-init clean --logs
sudo rm -rf /var/lib/cloud/

echo "[CLEAN] Removing SSH host keys (regenerated on each clone's first boot)..."
sudo rm -f /etc/ssh/ssh_host_*

echo "[CLEAN] Resetting machine-id..."
sudo truncate -s 0 /etc/machine-id

echo "[CLEAN] Clearing DHCP leases..."
sudo rm -f /var/lib/dhcp/dhclient.* /run/systemd/netif/leases/* 2>/dev/null || true

echo "[CLEAN] Clearing bash history..."
history -c; cat /dev/null > ~/.bash_history

echo "[DONE] Template maintenance complete. Shutting down..."
sudo shutdown -h now
REMOTECMDS

section "4 — Wait for Shutdown"
log "Waiting for VM to shut down..."
for i in $(seq 1 30); do
    STATUS=$(qm status "$TEMPLATE_ID" | awk '{print $2}')
    [[ "$STATUS" == "stopped" ]] && break
    sleep 5
done
[[ "$(qm status "$TEMPLATE_ID" | awk '{print $2}')" != "stopped" ]] && \
    { warn "VM did not shut down cleanly — forcing off"; qm stop "$TEMPLATE_ID"; sleep 5; }
log "VM is stopped"

section "5 — Re-convert to Template"
qm set "$TEMPLATE_ID" --template 1
log "VM $TEMPLATE_ID is now a template again"

section "Complete!"
echo ""
log "Template $TEMPLATE_ID has been updated and is ready to clone"
echo ""
echo "  Clone it:"
echo "  qm clone $TEMPLATE_ID <new-vmid> --name <new-name> --full"
echo ""
echo "  Recommended: run this script monthly to keep templates patched"
