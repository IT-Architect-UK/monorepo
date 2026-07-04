#!/usr/bin/env bash
# =============================================================================
# task-probe.sh — Semaphore task-context diagnostic
# Point a Semaphore task template's Playbook field at this script and run it
# to see exactly what execution context tasks get: user, cwd, shell, PATH,
# and which PROXMOX_*/PKR_VAR_*/SEMAPHORE_* variables arrive (secret VALUES
# are never printed — only names and lengths).
#
# Usage (Semaphore): set template Playbook to
#   automation/packer/scripts/task-probe.sh
# run the task, read the output, then set the Playbook back.
#
# Usage (shell): bash automation/packer/scripts/task-probe.sh
# =============================================================================
# NOTE: deliberately NO set -e — this script must survive anything and report.

echo "── task-probe ────────────────────────────────────────────"
echo "date      : $(date 2>&1)"
echo "user      : $(id 2>&1)"
echo "cwd       : $(pwd 2>&1)"
echo "bash      : ${BASH_VERSION:-not-bash}"
echo "script    : ${BASH_SOURCE[0]:-unset}"
echo "PATH      : ${PATH:-UNSET}"
echo "HOME      : ${HOME:-UNSET}"
echo "tty stdin : $([ -t 0 ] && echo yes || echo no)"
echo "argv      : $# args: $*"
echo "packer    : $(command -v packer 2>&1 || echo 'NOT FOUND')"
echo "jq        : $(command -v jq 2>&1 || echo 'NOT FOUND')"
echo "curl      : $(command -v curl 2>&1 || echo 'NOT FOUND')"
echo "git rev   : $(git rev-parse --short HEAD 2>&1)"
echo "/tmp write: $(touch /tmp/.probe 2>&1 && rm -f /tmp/.probe && echo yes || echo NO)"
echo "── relevant environment (values redacted to lengths) ─────"
env | grep -E '^(PROXMOX_|PKR_VAR_|SEMAPHORE_|ISO_)' | while IFS='=' read -r k v; do
    printf "  %-40s <%d chars>\n" "$k" "${#v}"
done
echo "── done — exit 0 ─────────────────────────────────────────"
exit 0
