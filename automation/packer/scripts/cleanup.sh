#!/usr/bin/env bash
# =============================================================================
# scripts/cleanup.sh
# =============================================================================
# Final cleanup run just before Packer captures the image.
# Called by every Packer template as the LAST provisioner step.
#
# This removes everything that must be unique per-VM:
#   - cloud-init cache (so it re-runs on first boot of each clone)
#   - SSH host keys (each clone generates its own on first boot)
#   - Machine ID (systemd unique identifier)
#   - DHCP leases
#   - Shell history and temp files
#
# DO NOT run this as a regular system admin script — it is ONLY for image sealing.
# =============================================================================

set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
log()     { echo -e "${GREEN}[✔]${NC} $*"; }
section() { echo -e "\n${BLUE}${BOLD}━━━ $* ━━━${NC}"; }

section "Image Seal — Removing Machine-Unique Data"

# cloud-init: must be cleaned so it re-runs on each clone's first boot.
# For Proxmox builds this is load-bearing, not just tidiness: provision.sh
# skips disable-cloud-init.sh for HYPERVISOR=proxmox specifically so this
# clean-and-let-it-rerun mechanism can set each clone's hostname from its
# Proxmox VM name (cloud_init=true in the Packer source block). For other
# hypervisors, disable-cloud-init.sh already ran, so this is a no-op safety
# net rather than something actively relied upon.
log "Cleaning cloud-init cache..."
sudo cloud-init clean --logs --seed
sudo rm -rf /var/lib/cloud/

# SSH host keys: each clone generates its own on first boot via ssh-keygen
log "Removing SSH host keys..."
sudo rm -f /etc/ssh/ssh_host_*

# machine-id: used by systemd/dbus to uniquely identify this host
log "Resetting machine-id..."
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -sf /etc/machine-id /var/lib/dbus/machine-id

# DHCP leases: reference the build VM's MAC address, not the clone's
log "Removing DHCP leases..."
sudo rm -f /var/lib/dhcp/dhclient.* 2>/dev/null || true
sudo find /run/systemd/netif/leases/ -type f -delete 2>/dev/null || true

# Apt cache: saves space in the image
log "Clearing apt cache..."
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*

# Temp files and logs
log "Clearing temp files and logs..."
sudo rm -rf /tmp/* /var/tmp/*
sudo find /var/log -type f -exec truncate -s 0 {} \;

# Shell history (build user's commands shouldn't be in the image)
log "Clearing shell history..."
unset HISTFILE
history -c
sudo rm -f /root/.bash_history ~/.bash_history

log "Image sealed and ready for capture"
