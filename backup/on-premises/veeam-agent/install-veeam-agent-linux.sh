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


section "Veeam Agent for Linux — Installation"

section "1 — Add Veeam Repository"
# Veeam's add_veeam_repos_ubuntu.sh (piped into bash here before) only
# installed this package: the apt source plus the signing key. Install it
# directly, pinned and checksummed — Veeam publishes no checksum, so this
# SHA256 was computed from the package as downloaded on 2026-09-02 and
# guards against any later change; bump both lines together on upgrade.
VEEAM_RELEASE_VERSION="${VEEAM_RELEASE_VERSION:-1.0.11}"
VEEAM_RELEASE_SHA256="${VEEAM_RELEASE_SHA256:-37849f2af797d15bf6e1f571b503bc54cd90cf8d8324dcadf11c97195ad84bd1}"
VEEAM_RELEASE_DEB="veeam-release-deb_${VEEAM_RELEASE_VERSION}_amd64.deb"
VEEAM_TMP="$(mktemp -d)"
trap 'rm -rf "${VEEAM_TMP}"' EXIT
wget -q -O "${VEEAM_TMP}/${VEEAM_RELEASE_DEB}" \
    "https://repository.veeam.com/backup/linux/agent/dpkg/debian/public/pool/veeam/v/veeam-release-deb/${VEEAM_RELEASE_DEB}" \
    || error "Could not download ${VEEAM_RELEASE_DEB}"
echo "${VEEAM_RELEASE_SHA256}  ${VEEAM_TMP}/${VEEAM_RELEASE_DEB}" | sha256sum -c - >/dev/null \
    || error "Checksum mismatch for ${VEEAM_RELEASE_DEB} — refusing to install. Verify the package and update VEEAM_RELEASE_SHA256."
dpkg -i "${VEEAM_TMP}/${VEEAM_RELEASE_DEB}"
log "Veeam repository added (veeam-release-deb ${VEEAM_RELEASE_VERSION}, checksum verified)"

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
