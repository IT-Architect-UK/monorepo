#!/usr/bin/env bash
# =============================================================================
# scripts/provision.sh
# =============================================================================
# Shell provisioner that runs INSIDE the build VM during the Packer build.
# Called by every Ubuntu Packer template (Proxmox, VMware, AWS, Azure, GCP).
#
# Environment variables (injected by the Packer template):
#   HYPERVISOR    — proxmox | vmware | aws | azure | gcp
#   COMPANY_NAME  — Organisation name for MOTD/banner (default: IT-Architect)
#
# Execution order:
#   1.  OS updates
#   2.  Baseline package install (iptables, fail2ban, python3, etc.)
#   3.  Hypervisor-specific guest agent (qemu-guest-agent OR open-vm-tools)
#   4.  apply-branding.sh   — MOTD, login banner, shell prompt colour
#   5.  disable-cloud-init.sh — Prevent cloud-init re-runs (fixes VMware networking)
#   6.  disable-ipv6.sh     — Disable IPv6 system-wide
#   7.  setup-iptables.sh   — iptables baseline ruleset (default-drop, RFC-1918 allow)
#   8.  SSH hardening       — Disable root login, key-only auth, enable banner
#   9.  Timezone            — IP geolocation detect, fall back to UTC
#   10. Kernel hardening    — sysctl: RP filter, SYN cookies, ASLR, no redirects
#   11. Services            — Enable fail2ban at boot
#
# Scripts in steps 4-7 are uploaded to /tmp/ by Packer file provisioners
# before this script runs. See the Packer template for the file provisioner
# definitions.
#
# Author  : IT-Architect-UK
# Repo    : https://github.com/IT-Architect-UK/monorepo
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
log()     { echo -e "${GREEN}[✔]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
fail()    { echo -e "${RED}[✘]${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BLUE}${BOLD}━━━ $* ━━━${NC}"; }

# ── Environment ───────────────────────────────────────────────────────────────
HYPERVISOR="${HYPERVISOR:-unknown}"
COMPANY_NAME="${COMPANY_NAME:-IT-Architect}"

section "Packer Provisioner — Ubuntu 24.04 Baseline"
log "Hypervisor : ${HYPERVISOR}"
log "Company    : ${COMPANY_NAME}"

# ── 1. OS Updates ─────────────────────────────────────────────────────────────
section "1 — OS Updates"
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get upgrade -y \
    -o Dpkg::Options::="--force-confdef" \
    -o Dpkg::Options::="--force-confold"
apt-get autoremove -y
apt-get clean
log "OS updates applied"

# ── 2. Baseline Packages ──────────────────────────────────────────────────────
section "2 — Baseline Packages"
apt-get install -y \
    curl wget git vim nano jq unzip \
    htop net-tools \
    ca-certificates gnupg lsb-release \
    apt-transport-https \
    python3 python3-pip \
    iptables iptables-persistent \
    netfilter-persistent \
    fail2ban \
    cloud-init \
    cloud-guest-utils \
    lvm2
log "Baseline packages installed"

# ── 3. Hypervisor Guest Agent ─────────────────────────────────────────────────
section "3 — Hypervisor Guest Agent"
case "${HYPERVISOR}" in
    proxmox|kvm)
        apt-get install -y qemu-guest-agent
        systemctl enable qemu-guest-agent
        systemctl start  qemu-guest-agent || true
        log "qemu-guest-agent installed and enabled (Proxmox/KVM)"
        ;;
    vmware)
        apt-get install -y open-vm-tools
        systemctl enable open-vm-tools
        systemctl start  open-vm-tools || true
        log "open-vm-tools installed and enabled (VMware)"
        ;;
    aws|azure|gcp)
        log "Cloud platform (${HYPERVISOR}) — cloud agent managed by platform, no guest tools needed"
        ;;
    *)
        warn "Unknown hypervisor '${HYPERVISOR}' — skipping guest agent installation"
        ;;
esac

# ── 4. Branding ───────────────────────────────────────────────────────────────
section "4 — Server Branding"
[[ -f /tmp/apply-branding.sh ]] || fail "apply-branding.sh not found in /tmp/ — check Packer file provisioner"
chmod +x /tmp/apply-branding.sh
/tmp/apply-branding.sh \
    --company "${COMPANY_NAME}" \
    --colour Cyan \
    --non-interactive
log "Branding applied for '${COMPANY_NAME}'"

# ── 5. Disable cloud-init ─────────────────────────────────────────────────────
section "5 — Disable cloud-init"
[[ -f /tmp/disable-cloud-init.sh ]] || fail "disable-cloud-init.sh not found in /tmp/ — check Packer file provisioner"
chmod +x /tmp/disable-cloud-init.sh
/tmp/disable-cloud-init.sh
log "cloud-init disabled (prevents networking issues on VMware and re-runs on clones)"

# ── 6. Disable IPv6 ───────────────────────────────────────────────────────────
section "6 — Disable IPv6"
[[ -f /tmp/disable-ipv6.sh ]] || fail "disable-ipv6.sh not found in /tmp/ — check Packer file provisioner"
chmod +x /tmp/disable-ipv6.sh
/tmp/disable-ipv6.sh
log "IPv6 disabled system-wide"

# ── 7. Firewall — iptables ────────────────────────────────────────────────────
section "7 — Firewall (iptables)"
[[ -f /tmp/setup-iptables.sh ]] || fail "setup-iptables.sh not found in /tmp/ — check Packer file provisioner"
chmod +x /tmp/setup-iptables.sh
/tmp/setup-iptables.sh
log "iptables baseline applied (default-drop INPUT, RFC-1918 allowed)"

# ── 8. SSH Hardening ──────────────────────────────────────────────────────────
section "8 — SSH Hardening"
SSHD_CONFIG="/etc/ssh/sshd_config"

sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "${SSHD_CONFIG}"
log "Root SSH login disabled"

sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "${SSHD_CONFIG}"
log "SSH password authentication disabled (key auth only)"

if grep -q "^Banner" "${SSHD_CONFIG}"; then
    sed -i 's|^Banner.*|Banner /etc/issue.net|' "${SSHD_CONFIG}"
elif grep -q "^#Banner" "${SSHD_CONFIG}"; then
    sed -i 's|^#Banner.*|Banner /etc/issue.net|' "${SSHD_CONFIG}"
else
    echo "Banner /etc/issue.net" >> "${SSHD_CONFIG}"
fi
log "SSH banner set to /etc/issue.net"

systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
log "SSH service restarted"

# ── 9. Timezone ───────────────────────────────────────────────────────────────
section "9 — Timezone"
DETECTED_TZ=""
if command -v curl &>/dev/null; then
    DETECTED_TZ=$(curl -sf --max-time 5 https://ipapi.co/timezone 2>/dev/null || true)
fi

if [[ -n "${DETECTED_TZ}" ]] && timedatectl list-timezones 2>/dev/null | grep -qxF "${DETECTED_TZ}"; then
    timedatectl set-timezone "${DETECTED_TZ}"
    log "Timezone set to ${DETECTED_TZ} (detected via IP geolocation)"
else
    timedatectl set-timezone UTC
    warn "Timezone detection failed or returned invalid value — defaulted to UTC"
fi

# ── 10. Kernel Hardening ──────────────────────────────────────────────────────
section "10 — Kernel Hardening"
tee /etc/sysctl.d/99-hardening.conf > /dev/null << 'SYSCTL'
# Reverse path filtering — drop packets with spoofed source addresses
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.rp_filter = 1
# SYN flood protection
net.ipv4.tcp_syncookies = 1
# Do not accept ICMP redirect messages (prevents MITM routing attacks)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
# Do not send ICMP redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
# Do not accept IP source route packets
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
# Address Space Layout Randomisation
kernel.randomize_va_space = 2
SYSCTL
sysctl --system &>/dev/null
log "Kernel hardening applied"

# ── 11. Services ──────────────────────────────────────────────────────────────
section "11 — Services"
systemctl enable fail2ban
log "fail2ban enabled at boot (SSH brute-force protection via iptables)"

# ── 12. Monorepo sync ─────────────────────────────────────────────────────────
section "12 — Monorepo sync"
# Install the sync script permanently so cron and admins can call it directly
cp /tmp/sync-monorepo.sh /usr/local/bin/sync-monorepo.sh
chmod +x /usr/local/bin/sync-monorepo.sh
log "sync-monorepo.sh installed to /usr/local/bin/"

# Cron job — @reboot (30s delay for network) and daily at 01:00
cat > /etc/cron.d/monorepo-sync << 'CRONEOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Sync IT-Architect monorepo — pulls latest scripts to /git/monorepo/
@reboot root sleep 30 && /usr/local/bin/sync-monorepo.sh >> /var/log/monorepo-sync.log 2>&1
0 1 * * * root /usr/local/bin/sync-monorepo.sh >> /var/log/monorepo-sync.log 2>&1
CRONEOF
chmod 644 /etc/cron.d/monorepo-sync
log "Cron jobs created: @reboot + daily 01:00 → /usr/local/bin/sync-monorepo.sh"

# Initial clone during Packer build (best-effort — doesn't fail the build)
log "Running initial monorepo clone ..."
/usr/local/bin/sync-monorepo.sh || warn "Initial clone failed — will retry on first boot"

# ── Summary ───────────────────────────────────────────────────────────────────
section "Provisioning Complete"
log "OS version : $(lsb_release -d | cut -f2)"
log "Kernel     : $(uname -r)"
log "Timezone   : $(timedatectl show --property=Timezone --value 2>/dev/null || date +%Z)"
log "Hypervisor : ${HYPERVISOR}"
log "Company    : ${COMPANY_NAME}"
echo ""
log "Packer will now run Ansible (server-baseline) then seal the image"
