#!/usr/bin/env bash
# =============================================================================
# prepare-ubuntu-2404-template.sh
# =============================================================================
# Prepares an Ubuntu 24.04 LTS VM to become a reusable VMware template.
#
# What this script does (run it INSIDE the Ubuntu VM):
#   1. Applies all OS updates
#   2. Installs open-vm-tools (VMware Tools for Linux)
#   3. Cleans cloud-init data so the next clone gets a fresh run
#   4. Removes machine-unique identifiers (hostname, SSH host keys, MAC leases)
#   5. Optionally installs cloud-init for automated customisation on first boot
#   6. Shuts the VM down so you can convert it to a template in vCenter
#
# Why do we need to clean these things?
# ──────────────────────────────────────
# If you clone a VM without cleaning it, every clone will have:
#   - The same hostname (network conflicts)
#   - The same SSH host keys (SSH will refuse connections or warn about MITM)
#   - DHCP leases that reference the original MAC address
#   - Cloud-init caches that prevent re-initialisation
#
# By removing them, each clone starts "fresh" — cloud-init runs again on
# first boot and sets the hostname, SSH keys, and user data unique to that VM.
#
# Prerequisites (run on the Ubuntu VM you want to templatise):
#   - Ubuntu 24.04 LTS installed and updated
#   - Internet access for apt packages
#   - Run as root
#
# Usage:
#   chmod +x prepare-ubuntu-2404-template.sh
#   sudo ./prepare-ubuntu-2404-template.sh
#
# After the script:
#   - The VM will shut down automatically
#   - Right-click the VM in vCenter → Convert to Template
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

# Must run as root
[[ $EUID -ne 0 ]] && error "This script must be run as root. Try: sudo $0"

section "Ubuntu 24.04 — VMware Template Preparation"
echo "This script will prepare this VM to become a reusable template."
echo "The VM will shut down at the end. Please ensure you have saved all work."
echo ""
read -rp "Continue? [y/N] " confirm
[[ "${confirm,,}" != "y" ]] && echo "Aborted." && exit 0

section "1 — Apply OS Updates"
log "Updating package lists..."
apt-get update -y

log "Applying all available upgrades..."
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold"

log "Removing unused packages..."
apt-get autoremove -y
apt-get clean
log "OS updates complete"

section "2 — Install open-vm-tools (VMware Tools)"
# open-vm-tools is the open-source implementation of VMware Tools.
# It enables: VM heartbeat detection, graceful shutdown, file copy,
# network configuration reporting, and clock synchronisation.
if dpkg -l open-vm-tools &>/dev/null; then
    log "open-vm-tools already installed. Ensuring latest version..."
    apt-get install --only-upgrade open-vm-tools -y
else
    log "Installing open-vm-tools..."
    apt-get install -y open-vm-tools
fi
log "open-vm-tools ready"

section "3 — Install cloud-init"
# cloud-init runs on first boot and configures: hostname, users, SSH keys,
# packages, network, and custom scripts. It is the standard way to customise
# VMware clones, and maps directly to AWS EC2 User Data / Azure Custom Script.
if ! dpkg -l cloud-init &>/dev/null; then
    log "Installing cloud-init..."
    apt-get install -y cloud-init
fi

# Configure cloud-init to use VMware's Guest Customisation as the data source
# This allows vCenter to inject hostname/network settings at clone time.
log "Configuring cloud-init datasource for VMware..."
cat > /etc/cloud/cloud.cfg.d/99-vmware-datasource.cfg << 'CLOUDINIT'
datasource_list: [VMware, OVF, NoCloud, None]
datasource:
  VMware:
    allow_raw_data: true
CLOUDINIT
log "cloud-init configured"

section "4 — Remove Machine-Unique Identifiers"

# 4a. Wipe cloud-init cache
# Without this, cloud-init will NOT re-run on the clone (it thinks it already ran)
log "Cleaning cloud-init instance data..."
cloud-init clean --logs --seed
rm -rf /var/lib/cloud/

# 4b. Remove SSH host keys
# Host keys uniquely identify a server to SSH clients. If clones share keys,
# SSH clients will display a "host key changed" warning (potential MITM attack).
# Each clone will auto-generate new unique host keys on first boot.
log "Removing SSH host keys (will be regenerated on first boot)..."
rm -f /etc/ssh/ssh_host_*

# 4c. Clear the hostname
# The clone will get a new hostname from cloud-init or vCenter customisation.
log "Resetting hostname..."
truncate -s 0 /etc/hostname
hostnamectl set-hostname localhost

# 4d. Remove DHCP leases
# Old leases reference the original VM's MAC address. After cloning, the clone
# has a new MAC, so old leases cause DHCP renewal problems.
log "Removing DHCP leases..."
rm -f /var/lib/dhcp/dhclient.*
rm -f /run/systemd/netif/leases/*
rm -f /var/lib/systemd/network/*.lease 2>/dev/null || true

# 4e. Clear machine-id
# The machine-id is used by systemd and dbus to uniquely identify the host.
# Clones must generate their own unique machine-id on first boot.
log "Clearing machine-id (will be regenerated on first boot)..."
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

# 4f. Clear bash history (optional security practice)
log "Clearing shell history..."
history -c
cat /dev/null > ~/.bash_history
find /home -name ".bash_history" -exec truncate -s 0 {} \;

section "5 — Final Cleanup"
log "Removing temporary files..."
rm -rf /tmp/* /var/tmp/*

log "Clearing apt cache..."
apt-get clean

log "Removing unnecessary log data..."
journalctl --vacuum-time=1d 2>/dev/null || true

section "6 — Summary"
echo ""
log "Template preparation complete!"
echo ""
echo "  Next steps in vCenter:"
echo "  ─────────────────────"
echo "  1. The VM will shut down in 10 seconds"
echo "  2. In vCenter, right-click the VM → 'Convert to Template'"
echo "  3. The template is now ready to clone"
echo ""
echo "  When you clone this template:"
echo "  ─────────────────────────────"
echo "  • Set a Customisation Spec (vCenter) to set hostname + network"
echo "  • Or let cloud-init handle it via user-data"
echo ""

warn "Shutting down in 10 seconds... Press Ctrl+C to cancel."
sleep 10
shutdown -h now
