#!/usr/bin/env bash
# =============================================================================
# install-veeam-agent-linux.sh
# =============================================================================
# Installs Veeam Agent for Linux (Free Edition).
#
# What is Veeam Agent for Linux?
# ────────────────────────────────
# Veeam Agent is enterprise-grade backup software with a free tier that
# supports:
#   - File-level backup and restore
#   - Volume-level backup
#   - Entire machine backup (image-level)
#   - Backup to local disk, NFS, or Veeam Backup & Replication server
#
# The free edition supports backup to a local repository only.
# For backup to Veeam B&R server or cloud, a licence is required.
#
# Prerequisites:
#   - Ubuntu 20.04, 22.04, or 24.04
#   - Internet access (to download from Veeam)
#   - Run as root
#
# Usage:
#   sudo ./install-veeam-agent-linux.sh
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

[[ $EUID -ne 0 ]] && error "Run as root: sudo $0"

UBUNTU_CODENAME=$(lsb_release -cs 2>/dev/null || echo "noble")

section "Veeam Agent for Linux — Installation"

section "1 — Add Veeam Repository"
wget -qO - https://www.veeam.com/downloads/add_veeam_repos_ubuntu.sh | bash
log "Veeam repository added"

section "2 — Install Veeam Agent"
apt-get update -q
apt-get install -y veeam
log "Veeam Agent installed: $(veeam --version 2>/dev/null || echo 'installed')"

section "3 — Initial Configuration"
warn "Veeam Agent requires interactive configuration via the text UI."
echo ""
echo "  Run the Veeam configuration wizard:"
echo "  sudo veeam"
echo ""
echo "  Or use the command-line interface:"
echo ""
echo "  # Create a local backup job"
echo "  veeamconfig job create filelevel \\"
echo "    --name 'Daily Backup' \\"
echo "    --reponame 'LocalRepo' \\"
echo "    --includedDirs /etc,/home,/var/www \\"
echo "    --daily --at 03:00"
echo ""
echo "  # List backup jobs"
echo "  veeamconfig job list"
echo ""
echo "  # Run a backup immediately"
echo "  veeamconfig job start --name 'Daily Backup'"
echo ""
echo "  # Check job status"
echo "  veeamconfig session list"
echo ""
echo "  Documentation: https://www.veeam.com/documentation-guides-datasheets.html"

section "Installation Complete!"
log "Veeam Agent for Linux is installed"
log "Run 'sudo veeam' to open the configuration wizard"
