#!/usr/bin/env bash
# =============================================================================
# Deployment Toolbox — Diagnostics Collector
# Runs a full health check of the toolbox server and writes everything to a
# single timestamped log file, suitable for sharing when something is off.
#
# Checks: OS/resources, monorepo sync state, service health (Semaphore,
# nginx, Docker, Webmin, SSH), Homepage container + config sanity, SSH
# authentication policy, firewall rules, Ansible/collection versions,
# listening ports, bootstrap state, and recent system errors.
#
# SAFE TO SHARE: secrets are never printed — the script reports which
# credential entries EXIST (names only), never their values.
#
# Usage:
#   sudo /git/monorepo/automation/packer/builds/ubuntu-2404-automation-toolbox/collect-diagnostics.sh
#
# Output:
#   /var/log/toolbox-diagnostics/toolbox-diagnostics-<timestamp>.log
#   (path is printed at the end — copy that file wherever you need it)
#
# Author:            Darren Pilkington
# Version:           1.0
# Date:              02-07-2026
# =============================================================================

set -uo pipefail   # deliberately NO -e: one failing probe must not stop the report

[[ "${EUID}" -eq 0 ]] || { echo "Run as root: sudo $0" >&2; exit 1; }

# Output path: default under /var/log, overridable for the Packer build
# (which downloads the report as a build artefact — see the .pkr.hcl).
LOG_DIR="/var/log/toolbox-diagnostics"
LOG_FILE="${1:-${LOG_DIR}/toolbox-diagnostics-$(date '+%Y%m%d-%H%M%S').log}"
mkdir -p "$(dirname "${LOG_FILE}")"

section() { printf '\n══ %s ═══════════════════════════════════════════════\n' "$1" >> "${LOG_FILE}"; }
run() { # run "label" command...
    local label="$1"; shift
    printf -- '\n-- %s\n$ %s\n' "${label}" "$*" >> "${LOG_FILE}"
    "$@" >> "${LOG_FILE}" 2>&1 || printf '[probe failed: exit %s]\n' "$?" >> "${LOG_FILE}"
}

echo "Collecting toolbox diagnostics — this takes ~15 seconds..."

# ─── System ──────────────────────────────────────────────────────────────────
section "SYSTEM"
run "Hostname / IP"     bash -c 'hostname -f 2>/dev/null || hostname; hostname -I'
run "OS release"        bash -c 'grep PRETTY_NAME /etc/os-release'
run "Uptime / load"     uptime
run "Memory"            free -h
run "Disk"              df -h /
run "Top processes"     bash -c 'ps aux --sort=-%mem | head -8'

# ─── Repo sync state ─────────────────────────────────────────────────────────
section "MONOREPO SYNC"
run "Checkout state"    git -C /git/monorepo log --oneline -3
run "Local changes"     git -C /git/monorepo status --short
run "Sync timer/cron"   bash -c 'crontab -l 2>/dev/null | grep -i sync; ls -la /usr/local/bin/sync-monorepo.sh 2>/dev/null'

# ─── Services ────────────────────────────────────────────────────────────────
section "SERVICES"
for svc in semaphore nginx docker webmin ssh; do
    run "systemctl ${svc}" bash -c "systemctl is-active ${svc} 2>&1; systemctl is-enabled ${svc} 2>&1"
done
run "Failed units"      systemctl --failed --no-pager
run "Semaphore version" bash -c 'semaphore version 2>/dev/null | head -1'
run "Semaphore DB dialect" bash -c 'jq -r .dialect /etc/semaphore/config.json 2>/dev/null || grep -o "\"dialect\":[^,]*" /etc/semaphore/config.json'
run "Semaphore API ping" curl -fsS --max-time 5 http://127.0.0.1:3000/api/ping
run "Semaphore recent errors" bash -c 'journalctl -u semaphore -p warning --no-pager -n 20 --output cat 2>/dev/null | tail -20'
run "nginx config test" nginx -t

# ─── Homepage ────────────────────────────────────────────────────────────────
section "HOMEPAGE DASHBOARD"
run "Container status"  bash -c 'docker ps -a --filter name=homepage --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
run "Container logs"    bash -c 'docker logs homepage --tail 25 2>&1'
run "HTTP response"     bash -c 'curl -fsS -o /dev/null -w "HTTP %{http_code} in %{time_total}s\n" --max-time 5 http://127.0.0.1:3002/'
run "Leftover placeholders" bash -c 'grep -c "toolbox.lab.local" /opt/homepage/config/services.yaml 2>/dev/null && echo "^ placeholder hostnames still present (bootstrap not run?)" || echo "none — good"'
run "Widget credential entries (names only)" bash -c 'grep -oE "^HOMEPAGE_VAR_[A-Z_]+" /opt/homepage/.env.homepage 2>/dev/null; awk -F= "/^HOMEPAGE_VAR/ {print \$1 \"=\" (length(\$2)>0 ? \"<set>\" : \"<EMPTY>\")}" /opt/homepage/.env.homepage 2>/dev/null'

# ─── SSH policy ──────────────────────────────────────────────────────────────
section "SSH AUTHENTICATION POLICY"
run "Global password auth" bash -c 'sshd -T 2>/dev/null | grep -E "^(passwordauthentication|permitrootlogin|pubkeyauthentication)"'
run "Per-user Match blocks" bash -c 'grep -A2 "^Match User" /etc/ssh/sshd_config || echo "no Match blocks — password SSH disabled for ALL accounts"'
run "sshd_config.d drop-ins" bash -c 'ls -la /etc/ssh/sshd_config.d/ 2>/dev/null; grep -r "PasswordAuthentication" /etc/ssh/sshd_config.d/ 2>/dev/null'
run "sshd config valid"  sshd -t

# ─── Firewall ────────────────────────────────────────────────────────────────
section "FIREWALL"
run "Active rules"      iptables -L INPUT -n -v --line-numbers
run "Default policies"  bash -c 'iptables -S | head -3'
run "Persisted rules"   bash -c 'ls -la /etc/iptables/rules.v4 2>/dev/null && echo "--- diff vs active:" && bash -c "diff <(iptables-save | grep \"^-A INPUT\") <(grep \"^-A INPUT\" /etc/iptables/rules.v4) && echo identical"'
run "Strict mode check" bash -c 'iptables -S INPUT | grep -q "192.168.0.0/16 -j ACCEPT" && echo "BASELINE mode (blanket RFC-1918 accept — bootstrap lockdown not applied)" || echo "strict/custom rules in effect"'

# ─── Automation tooling ──────────────────────────────────────────────────────
section "AUTOMATION TOOLING"
run "Ansible version"   bash -c 'ansible --version | head -2'
run "Key collections"   bash -c 'ansible-galaxy collection list 2>/dev/null | grep -E "community.proxmox|community.hashi_vault|community.general" | sort -u'
run "Python deps"       bash -c 'python3 -c "import proxmoxer; print(\"proxmoxer\", proxmoxer.__version__)" 2>&1; python3 -c "import hvac; print(\"hvac\", hvac.__version__)" 2>&1'
run "Packer / Terraform / Docker" bash -c 'packer --version 2>&1 | head -1; terraform --version 2>&1 | head -1; docker --version'

# ─── Network ─────────────────────────────────────────────────────────────────
section "NETWORK"
run "Listening ports"   ss -tlnp
run "DNS resolution"    bash -c 'resolvectl status 2>/dev/null | grep -E "DNS Servers|Current DNS" | head -4'
run "Outbound (GitHub)" bash -c 'curl -fsS -o /dev/null -w "HTTP %{http_code}\n" --max-time 8 https://github.com'

# ─── Bootstrap state ─────────────────────────────────────────────────────────
section "BOOTSTRAP STATE"
run "Bootstrap marker"  bash -c '[ -f /opt/toolbox/.bootstrapped ] && echo "bootstrapped: yes ($(stat -c %y /opt/toolbox/.bootstrapped))" || echo "bootstrapped: NO — run bootstrap-toolbox.sh"'

# ─── Recent system errors ────────────────────────────────────────────────────
section "RECENT SYSTEM ERRORS (this boot)"
run "journalctl -p err" bash -c 'journalctl -p err -b --no-pager -n 30 --output short 2>/dev/null | tail -30'

# ─── Done ────────────────────────────────────────────────────────────────────
# 600 for ad-hoc runs; the build override passes a /tmp path and loosens
# this itself so Packer's ssh user can download the artefact.
chmod 600 "${LOG_FILE}"
echo ""
echo "Diagnostics written to: ${LOG_FILE}"
echo "Secrets are redacted (names only) — the file is safe to share."
