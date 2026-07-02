#!/usr/bin/env bash
# =============================================================================
# scripts/verify-monorepo-sync.sh
# =============================================================================
# Pre-flight check run before the automation toolbox's self-provisioning
# Ansible playbook (see the Packer template's ansible-playbook provisioner).
#
# roles/common/tasks/main.yml references infrastructure/networking/firewall/
# setup-iptables.sh via a path relative to playbook_dir. That only resolves
# correctly when Ansible runs against a FULL monorepo checkout -- which is
# exactly what provision.sh (step 12) clones to /git/monorepo via
# sync-monorepo.sh. But that initial clone is deliberately best-effort
# (sync-monorepo.sh exits 0 even on failure, expecting a retry on next boot
# or the daily cron run) -- fine for ongoing operation, not fine for a step
# that's about to depend on the clone existing right now.
#
# This script turns that best-effort clone into a hard gate for THIS build:
# if the cron job, the clone, or the specific files the next step needs
# aren't there, it fails here with a specific, actionable reason -- instead
# of ansible-playbook failing a few tasks in with a bare "could not find or
# access" error that doesn't say why the file is missing.
#
# Author  : IT-Architect-UK
# Repo    : https://github.com/IT-Architect-UK/monorepo
# =============================================================================

set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[✔]${NC} $*"; }
fail() { echo -e "${RED}[✘]${NC} $*" >&2; }

REPO_DIR="/git/monorepo"
CRON_FILE="/etc/cron.d/monorepo-sync"
SYNC_LOG="/var/log/monorepo-sync.log"

STATUS=0

# ── 1. Cron job installed ────────────────────────────────────────────────────
if [[ -f "${CRON_FILE}" ]]; then
    ok "Monorepo sync cron job present (${CRON_FILE})"
else
    fail "Monorepo sync cron job MISSING (${CRON_FILE} not found)."
    fail "  -> provision.sh step 12 ('Monorepo sync') did not run or did not"
    fail "     complete. Check earlier build output for that section."
    STATUS=1
fi

# ── 2. Repo cloned ───────────────────────────────────────────────────────────
if [[ -d "${REPO_DIR}/.git" ]]; then
    HEAD_REF="$(git -C "${REPO_DIR}" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
    ok "Monorepo present at ${REPO_DIR} (HEAD: ${HEAD_REF})"
else
    fail "Monorepo NOT found at ${REPO_DIR} (no .git directory)."
    fail "  -> The initial clone in provision.sh step 12 likely failed."
    fail "     sync-monorepo.sh treats clone failure as non-fatal (exit 0)"
    fail "     and expects a retry on first boot -- but this build needs"
    fail "     it available right now."
    if [[ -f "${SYNC_LOG}" ]]; then
        fail "  -> Last 10 lines of ${SYNC_LOG}:"
        tail -n 10 "${SYNC_LOG}" | sed 's/^/       /' >&2
    else
        fail "  -> ${SYNC_LOG} does not exist either -- sync-monorepo.sh may"
        fail "     never have run. Check network/DNS/GitHub reachability"
        fail "     from inside the build VM."
    fi
    STATUS=1
fi

# ── 3. Expected content present (repo isn't empty/partial) ──────────────────
if [[ ${STATUS} -eq 0 ]]; then
    REQUIRED_FILES=(
        "automation/ansible/playbooks/server-baseline.yml"
        "automation/ansible/roles/common/tasks/main.yml"
        "infrastructure/networking/firewall/setup-iptables.sh"
    )
    for f in "${REQUIRED_FILES[@]}"; do
        if [[ -f "${REPO_DIR}/${f}" ]]; then
            ok "Found ${f}"
        else
            fail "Expected file MISSING: ${REPO_DIR}/${f}"
            fail "  -> Clone may be incomplete, on the wrong branch, or the"
            fail "     repo structure changed since this check was written."
            STATUS=1
        fi
    done
fi

echo ""
if [[ ${STATUS} -ne 0 ]]; then
    fail "Monorepo sync verification FAILED -- see above for the specific reason."
    fail "The self-provisioning Ansible run depends on a complete monorepo"
    fail "clone at ${REPO_DIR} and will not be attempted."
    exit 1
fi

ok "Monorepo sync verified -- proceeding to Ansible self-provisioning."
exit 0
