#!/usr/bin/env bash
# =============================================================================
# sync-monorepo.sh
# =============================================================================
# Clones or pulls the latest IT-Architect monorepo to /opt/monorepo.
#
# Installed to /usr/local/bin/sync-monorepo.sh by provision.sh.
# Triggered automatically:
#   • On every boot  (waits 30s for network)
#   • Daily at 01:00 (via /etc/cron.d/monorepo-sync)
#
# After the sync, all repo scripts are available under /opt/monorepo/:
#   /opt/monorepo/infrastructure/servers/linux/configuration/
#   /opt/monorepo/infrastructure/servers/windows/os/
#   /opt/monorepo/infrastructure/networking/firewall/
#   /opt/monorepo/automation/ansible/
#   etc.
#
# Failure handling:
#   The script logs errors but exits 0 so cron does not spam root@localhost.
#   If GitHub is unreachable the existing local copy remains intact.
#
# Author  : IT-Architect-UK
# Repo    : https://github.com/IT-Architect-UK/monorepo
# =============================================================================

REPO_URL="https://github.com/IT-Architect-UK/monorepo.git"
REPO_DIR="/opt/monorepo"
LOG_FILE="/var/log/monorepo-sync.log"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

log()  { echo "[${TIMESTAMP}] [INFO]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[${TIMESTAMP}] [WARN]  $*" | tee -a "${LOG_FILE}"; }
err()  { echo "[${TIMESTAMP}] [ERROR] $*" | tee -a "${LOG_FILE}"; }

log "Monorepo sync starting on $(hostname)"

# ── Ensure git is available ────────────────────────────────────────────────────
if ! command -v git &>/dev/null; then
    err "git not found — cannot sync. Install git and re-run."
    exit 0   # Exit 0 so cron does not fail noisily
fi

# ── Ensure parent directory exists ────────────────────────────────────────────
mkdir -p "$(dirname "${REPO_DIR}")"

# ── Connectivity check (soft) ─────────────────────────────────────────────────
if ! curl -sf --max-time 10 --head "https://github.com" &>/dev/null; then
    warn "GitHub not reachable — skipping sync. Existing copy is unchanged."
    exit 0
fi

# ── Clone or pull ─────────────────────────────────────────────────────────────
if [ -d "${REPO_DIR}/.git" ]; then
    log "Pulling latest changes into ${REPO_DIR} ..."
    if git -C "${REPO_DIR}" pull --ff-only --quiet 2>>"${LOG_FILE}"; then
        log "Pull complete. HEAD: $(git -C "${REPO_DIR}" rev-parse --short HEAD)"
    else
        warn "Pull failed (possible merge conflict or detached HEAD). Recloning ..."
        rm -rf "${REPO_DIR}"
        if git clone --quiet "${REPO_URL}" "${REPO_DIR}" 2>>"${LOG_FILE}"; then
            log "Reclone complete. HEAD: $(git -C "${REPO_DIR}" rev-parse --short HEAD)"
        else
            err "Reclone failed. Check ${LOG_FILE} for details."
        fi
    fi
else
    log "Cloning ${REPO_URL} into ${REPO_DIR} ..."
    if git clone --quiet "${REPO_URL}" "${REPO_DIR}" 2>>"${LOG_FILE}"; then
        log "Clone complete. HEAD: $(git -C "${REPO_DIR}" rev-parse --short HEAD)"
    else
        err "Clone failed. Check ${LOG_FILE} for details."
    fi
fi

log "Monorepo sync finished."
