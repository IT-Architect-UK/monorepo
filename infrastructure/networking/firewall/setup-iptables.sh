#!/usr/bin/env bash
# =============================================================================
# IPTables Baseline Firewall — Ubuntu
# Applies a defence-in-depth iptables ruleset suitable for infrastructure
# servers. Two modes:
#
#   Default mode (no MGMT_SUBNETS): allows SSH from anywhere and ICMP from
#   RFC-1918 private subnets. Nothing else. Suitable as a first-boot baseline
#   for a server whose LAN you have not yet vetted — including a cloud VM,
#   where "private" ranges may belong to other tenants.
#
#     TRUSTED_SUBNETS (optional) opens ALL ports to the listed CIDRs on top of
#     that baseline — the old "trust the whole LAN" behaviour, now explicit.
#
#   Strict mode (MGMT_SUBNETS set): allows ONLY the listed TCP ports and
#   ICMP, ONLY from the listed subnets. Everything else is dropped —
#   including other private/RFC-1918 addresses and SSH from the internet.
#
# Environment variables:
#   MGMT_SUBNETS       Comma-separated CIDRs allowed in (e.g. "192.168.4.0/24")
#                      Setting this switches the script to strict mode.
#   ALLOWED_TCP_PORTS  Comma-separated TCP ports to allow from MGMT_SUBNETS
#                      (default: the SSH port only)
#   TRUSTED_SUBNETS    Default mode only. Comma-separated CIDRs allowed in on
#                      every port and protocol (e.g. "192.168.4.0/24").
#                      Ignored in strict mode. If unset, a .env file beside
#                      this script is sourced (see .env.example) — keep your
#                      subnets there, never in the repo.
#   EXTRA_RULES        Additional ACCEPT rules, both modes. Semicolon-separated
#                      entries of proto:port[:source], e.g.
#                      "tcp:10000:192.168.4.0/24;tcp:9100". Declared in
#                      Ansible as firewall_extra_rules, so they are part of
#                      the baseline and survive every re-apply.
#
# Hand-added rules survive too: the script owns a LOCAL-INPUT chain that
# INPUT jumps to after the baseline. Anything you add there by hand or via
# Webmin (iptables -A LOCAL-INPUT ...) is saved before the flush and
# restored after it. Rules added directly to INPUT are NOT preserved.
#
# Example (Deployment Toolbox, strict):
#   sudo MGMT_SUBNETS="192.168.4.0/24" ALLOWED_TCP_PORTS="22,80,3002,10000" \
#        ./setup-iptables.sh
#
# Example (home lab server, baseline plus a trusted LAN):
#   sudo TRUSTED_SUBNETS="192.168.4.0/24" ./setup-iptables.sh
#
# WARNING: in strict mode, run this from the console or from a host INSIDE
# MGMT_SUBNETS — an SSH session from outside it will be cut off.
# Drops all other inbound traffic. Saves rules persistently via
# iptables-persistent.
#
# Default policy:
#   INPUT   — DROP  (allowlist model)
#   FORWARD — DROP
#   OUTPUT  — ACCEPT
#
# Allowed inbound (default mode):
#   - Loopback (lo)
#   - Established / related connections
#   - SSH (port auto-detected from sshd_config, default 22)
#   - ICMP from 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
#   - Everything from TRUSTED_SUBNETS, if set
#   - EXTRA_RULES, then whatever is in LOCAL-INPUT (both modes)
#
# Usage:
#   sudo ./setup-iptables.sh
#   sudo ./setup-iptables.sh --ssh-port 2222
#
# Options:
#   --ssh-port <port>   Override SSH port (auto-detected by default)
#
# Author:            Darren Pilkington
# Version:           1.3
# Date:              02-09-2026
# =============================================================================

set -euo pipefail

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/firewall-setup"
LOG_FILE="${LOG_DIR}/setup-iptables-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── Argument parsing ────────────────────────────────────────────────────────
SSH_PORT_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssh-port) SSH_PORT_OVERRIDE="$2"; shift 2 ;;
        --help)
            grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,2\}//'
            exit 0
            ;;
        *) fail "Unknown argument: $1. Use --help for usage." ;;
    esac
done

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]]          || fail "Run as root: sudo ./setup-iptables.sh"
command -v iptables &>/dev/null || fail "iptables not found."

log "Configuring iptables on $(hostname -f 2>/dev/null || hostname)"
log "Log file: ${LOG_FILE}"

# ─── Detect SSH port ─────────────────────────────────────────────────────────
if [[ -n "${SSH_PORT_OVERRIDE}" ]]; then
    SSH_PORT="${SSH_PORT_OVERRIDE}"
else
    SSH_PORT=$(grep -E "^Port " /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -1 || true)
    SSH_PORT="${SSH_PORT:-22}"
fi
log "SSH port: ${SSH_PORT}"

# ─── Subnet / port configuration ─────────────────────────────────────────────
PRIVATE_SUBNETS=("10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16")
MGMT_SUBNETS="${MGMT_SUBNETS:-}"
ALLOWED_TCP_PORTS="${ALLOWED_TCP_PORTS:-}"
TRUSTED_SUBNETS="${TRUSTED_SUBNETS:-}"
EXTRA_RULES="${EXTRA_RULES:-}"
LOCAL_CHAIN="LOCAL-INPUT"

# Site values live in a git-ignored .env beside this script (see .env.example).
# Only consulted when nothing was passed in the environment.
if [[ -z "${TRUSTED_SUBNETS}" ]]; then
    ENV_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.env"
    if [[ -f "${ENV_FILE}" ]]; then
        # shellcheck disable=SC1090
        source "${ENV_FILE}"
        TRUSTED_SUBNETS="${TRUSTED_SUBNETS:-}"
        EXTRA_RULES="${EXTRA_RULES:-}"
        log "Loaded site values from ${ENV_FILE}"
    fi
fi

# ─── Validate EXTRA_RULES before touching anything ───────────────────────────
# A typo must fail here, not after the flush with a half-built ruleset.
EXTRA_LIST=()
if [[ -n "${EXTRA_RULES}" ]]; then
    IFS=';' read -ra _raw <<< "${EXTRA_RULES}"
    for entry in "${_raw[@]}"; do
        entry="$(echo "${entry}" | xargs)"
        [[ -n "${entry}" ]] || continue
        IFS=':' read -r e_proto e_port e_src <<< "${entry}"
        [[ "${e_proto}" =~ ^(tcp|udp)$ ]] || fail "EXTRA_RULES: bad protocol in '${entry}' (tcp or udp)"
        [[ "${e_port}" =~ ^[0-9]+(:[0-9]+)?$ ]] || fail "EXTRA_RULES: bad port in '${entry}'"
        [[ -z "${e_src:-}" || "${e_src}" =~ ^[0-9a-fA-F.:]+(/[0-9]+)?$ ]] || fail "EXTRA_RULES: bad source in '${entry}'"
        EXTRA_LIST+=("${entry}")
    done
fi

# ─── Preserve the LOCAL-INPUT chain across the flush ─────────────────────────
# Hand-added rules live in LOCAL-INPUT (see header). Capture them now so the
# rebuild below can put them back; anything added straight to INPUT is lost.
LOCAL_RULES=()
if iptables -S "${LOCAL_CHAIN}" &>/dev/null; then
    mapfile -t LOCAL_RULES < <(iptables -S "${LOCAL_CHAIN}" | grep -E "^-A ${LOCAL_CHAIN} " || true)
    log "Preserving ${#LOCAL_RULES[@]} rule(s) from ${LOCAL_CHAIN}"
fi

# ─── Flush existing rules and reset policies ─────────────────────────────────
log "Flushing existing iptables rules..."
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

log "Setting default chain policies..."
iptables -P INPUT   DROP
iptables -P FORWARD DROP
iptables -P OUTPUT  ACCEPT
log "Default policies: INPUT=DROP, FORWARD=DROP, OUTPUT=ACCEPT"

# ─── Loopback ────────────────────────────────────────────────────────────────
log "Allowing loopback traffic..."
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# ─── Established and related connections ─────────────────────────────────────
log "Allowing established and related inbound connections..."
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

if [[ -n "${MGMT_SUBNETS}" ]]; then
    # ─── STRICT MODE: named subnets and ports only ───────────────────────────
    PORTS="${ALLOWED_TCP_PORTS:-${SSH_PORT}}"
    log "STRICT mode: allowing TCP port(s) ${PORTS} and ICMP from ${MGMT_SUBNETS} only"
    IFS=',' read -ra SUBNET_LIST <<< "${MGMT_SUBNETS}"
    IFS=',' read -ra PORT_LIST   <<< "${PORTS}"
    for subnet in "${SUBNET_LIST[@]}"; do
        subnet="$(echo "${subnet}" | xargs)"
        for port in "${PORT_LIST[@]}"; do
            port="$(echo "${port}" | xargs)"
            iptables -A INPUT -s "${subnet}" -p tcp --dport "${port}" -j ACCEPT
            log "  Allowed: tcp/${port} from ${subnet}"
        done
        iptables -A INPUT -s "${subnet}" -p icmp -j ACCEPT
        log "  Allowed: icmp from ${subnet}"
    done
    log "All other inbound traffic (including other private subnets) is DROPPED."
else
    # ─── DEFAULT MODE: baseline for freshly built servers ────────────────────
    log "DEFAULT mode: SSH from anywhere, ICMP from private subnets"

    log "Allowing SSH on port ${SSH_PORT}..."
    iptables -A INPUT -p tcp --dport "${SSH_PORT}" -j ACCEPT

    log "Allowing ICMP from private subnets..."
    for subnet in "${PRIVATE_SUBNETS[@]}"; do
        iptables -A INPUT -s "${subnet}" -p icmp -j ACCEPT
        log "  Allowed: icmp from ${subnet}"
    done

    if [[ -n "${TRUSTED_SUBNETS}" ]]; then
        log "Allowing ALL inbound traffic from trusted subnets..."
        IFS=',' read -ra TRUSTED_LIST <<< "${TRUSTED_SUBNETS}"
        for subnet in "${TRUSTED_LIST[@]}"; do
            subnet="$(echo "${subnet}" | xargs)"
            [[ -n "${subnet}" ]] || continue
            iptables -A INPUT -s "${subnet}" -j ACCEPT
            log "  Allowed: all from ${subnet}"
        done
    else
        log "No TRUSTED_SUBNETS set — private subnets get ICMP only."
    fi
    log "All other inbound traffic is DROPPED."
fi

# ─── Extra rules (both modes) ────────────────────────────────────────────────
# Declared per host/group in Ansible (firewall_extra_rules) and passed in as
# EXTRA_RULES: "proto:port[:source];..." — part of the baseline, so they are
# re-applied every time rather than lost to the flush.
if [[ ${#EXTRA_LIST[@]} -gt 0 ]]; then
    log "Applying extra rules..."
    for entry in "${EXTRA_LIST[@]}"; do
        IFS=':' read -r e_proto e_port e_src <<< "${entry}"
        if [[ -n "${e_src:-}" ]]; then
            iptables -A INPUT -s "${e_src}" -p "${e_proto}" --dport "${e_port}" -j ACCEPT
            log "  Allowed: ${e_proto}/${e_port} from ${e_src}"
        else
            iptables -A INPUT -p "${e_proto}" --dport "${e_port}" -j ACCEPT
            log "  Allowed: ${e_proto}/${e_port} from anywhere"
        fi
    done
fi

# ─── LOCAL-INPUT: the chain for hand-added rules ─────────────────────────────
# Rebuilt last, and INPUT jumps to it last, so it can only ever ADD accepts on
# top of the baseline. Anything it does not match returns to INPUT's DROP.
iptables -N "${LOCAL_CHAIN}"
for rule in "${LOCAL_RULES[@]}"; do
    # shellcheck disable=SC2086  # each saved rule is a ready-made argv line
    iptables ${rule}
done
iptables -A INPUT -j "${LOCAL_CHAIN}"
if [[ ${#LOCAL_RULES[@]} -gt 0 ]]; then
    log "${LOCAL_CHAIN} restored with ${#LOCAL_RULES[@]} rule(s). Add site-specific rules there: iptables -A ${LOCAL_CHAIN} ..."
else
    log "${LOCAL_CHAIN} created (empty). Add site-specific rules there: iptables -A ${LOCAL_CHAIN} ..."
fi

# ─── Install iptables-persistent ─────────────────────────────────────────────
log "Installing iptables-persistent for rule persistence across reboots..."
DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent \
    2>&1 | tee -a "${LOG_FILE}"

# ─── Save rules ──────────────────────────────────────────────────────────────
log "Saving iptables rules to /etc/iptables/rules.v4..."
mkdir -p /etc/iptables
iptables-save | tee /etc/iptables/rules.v4 > /dev/null
log "Rules saved."

# ─── Display active rules ────────────────────────────────────────────────────
log "Active iptables rules:"
iptables -L -n -v 2>&1 | tee -a "${LOG_FILE}"

log "Firewall configuration complete. Log: ${LOG_FILE}"
