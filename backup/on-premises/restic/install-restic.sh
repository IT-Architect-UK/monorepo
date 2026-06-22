#!/usr/bin/env bash
# =============================================================================
# install-restic.sh
# =============================================================================
# Installs Restic — a fast, encrypted, deduplicated backup tool.
#
# Why Restic?
# ───────────
# Restic is the modern standard for self-managed backups. Compared to rsync
# or tar-based solutions:
#
#   Feature              rsync / tar    Restic
#   ─────────────────────────────────────────
#   Encryption           ❌             ✅ (AES-256 always on)
#   Deduplication        ❌             ✅ (only stores changed blocks)
#   Multiple backends    Limited        ✅ (local, S3, B2, Azure, GCP, SSH)
#   Snapshot history     Manual         ✅ (automatic, with retention policy)
#   Integrity checking   Manual         ✅ (built-in verify command)
#   Mounting backups     ❌             ✅ (browse as filesystem)
#
# Prerequisites:
#   - Ubuntu 22.04 / 24.04
#   - Run as root
#
# Usage:
#   sudo ./install-restic.sh
#
# After installation, see:
#   - backup-to-local.sh   — Back up to a local disk
#   - backup-to-s3.sh      — Back up to AWS S3 (or compatible)
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

section "Restic Installation"

section "1 — Install via apt"
apt-get update -q
apt-get install -y restic
log "Restic installed: $(restic version)"

section "2 — Self-update to latest version"
restic self-update 2>/dev/null && log "Updated to latest version" || warn "Self-update skipped (binary may be read-only via apt)"

section "Installation Complete!"
echo ""
log "Restic is ready to use. Next steps:"
echo ""
echo "  1. Initialise a backup repository:"
echo "     restic init --repo /mnt/backup/myrepo"
echo ""
echo "  2. Run your first backup:"
echo "     restic --repo /mnt/backup/myrepo backup /etc /home"
echo ""
echo "  3. List snapshots:"
echo "     restic --repo /mnt/backup/myrepo snapshots"
echo ""
echo "  4. Restore a file:"
echo "     restic --repo /mnt/backup/myrepo restore latest --target /tmp/restore"
echo ""
echo "  See backup-to-local.sh and backup-to-s3.sh for automated setups."
