#!/usr/bin/env bash
# =============================================================================
# scripts/provision.sh
# =============================================================================
# Shell provisioner that runs INSIDE the build VM during the Packer build.
#
# This script is called by every Packer template (Proxmox, VMware, AWS, Azure,
# GCP) — making the resulting image consistent across all platforms.
#
# Execution order during a Packer build:
#   1. Packer launches a temporary VM from the base OS image
#   2. Packer SSHes in (or uses WinRM)
#   3. THIS SCRIPT runs via the shell provisioner
#   4. Ansible provisioner runs (calls our server-baseline role)
#   5. Packer seals the image (cloud-init clean, host key removal)
#   6. Packer creates the final image / template and destroys the build VM
#
# What this script does:
#   - Updates all OS packages
#   - Installs common tools and the cloud-init datasource for the target platform
#   - Configures best-practice OS settings
#   - Does NOT remove SSH keys or cloud-init data — the Packer template handles
#     that in a separate "cleanup" step so Packer can still connect
#
# Author  : IT-Architect-UK
# Repo    : https://github.com/IT-Architect-UK/monorepo
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
log()     { echo -e "${GREEN}[✔]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
section() { echo -e "\n${BLUE}${BOLD}━━━ $* ━━━${NC}"; }

section "Packer Provisioner — Ubuntu 24.04 Baseline"

section "1 — OS Updates"
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -q
sudo apt-get upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"
sudo apt-get autoremove -y
sudo apt-get clean
log "OS updates applied"

section "2 — Install Common Tools"
sudo apt-get install -y \
    curl wget git vim nano jq unzip \
    htop net-tools nmap \
    ca-certificates gnupg lsb-release \
    apt-transport-https \
    python3 python3-pip \
    open-vm-tools \
    cloud-init \
    qemu-guest-agent \
    fail2ban \
    ufw
log "Common tools installed"

section "3 — OS Hardening"
# Disable root SSH login
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
log "Root SSH login disabled"

# Set password authentication based on build — will be overridden by cloud-init on first boot
sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
log "SSH password authentication disabled (key auth only)"

# Configure sysctl hardening
sudo tee /etc/sysctl.d/99-hardening.conf > /dev/null << 'SYSCTL'
# Network security
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_redirects = 0
# Kernel hardening
kernel.randomize_va_space = 2
SYSCTL
sudo sysctl --system &>/dev/null
log "Kernel hardening applied"

# Configure UFW — basic ruleset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw --force enable
log "UFW firewall enabled (SSH allowed)"

section "4 — Configure cloud-init"
# cloud-init is what AWS/Azure/GCP/VMware use to inject:
#   - Hostname
#   - SSH public key for the admin user
#   - Custom startup scripts (user-data)
# The datasource list tells cloud-init where to look for configuration.
# We include all major providers — cloud-init picks the right one automatically.
sudo tee /etc/cloud/cloud.cfg.d/99-packer.cfg > /dev/null << 'CLOUDINIT'
# Datasource priority — cloud-init tries these in order
datasource_list:
  - NoCloud      # Proxmox: reads from cloud-init drive attached to VM
  - ConfigDrive  # OpenStack / VMware vSphere Guest Customisation
  - VMware       # VMware with open-vm-tools
  - Ec2          # AWS EC2
  - Azure        # Microsoft Azure
  - GCEInst      # Google Compute Engine
  - None

# Enable the modules needed for hostname, users, SSH keys
cloud_config_modules:
  - set_hostname
  - update_hostname
  - update_etc_hosts
  - users-groups
  - ssh

cloud_final_modules:
  - scripts-user
  - final-message
CLOUDINIT
log "cloud-init configured for multi-platform datasource"

section "5 — Enable Services"
sudo systemctl enable qemu-guest-agent 2>/dev/null || true
sudo systemctl enable fail2ban
sudo systemctl enable open-vm-tools 2>/dev/null || true
log "Services enabled"

section "6 — System Info"
echo ""
log "Ubuntu version : $(lsb_release -d | cut -f2)"
log "Kernel         : $(uname -r)"
log "Disk free      : $(df -h / | awk 'NR==2{print $4}')"
log "Packages updated: $(apt list --upgradable 2>/dev/null | wc -l) remaining"
echo ""
log "Provisioning complete — Packer will now seal and capture the image"
