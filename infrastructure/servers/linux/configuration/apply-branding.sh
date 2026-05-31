#!/usr/bin/env bash
# =============================================================================
# Apply Server Branding — Ubuntu
# Configures the login banner, MOTD, and shell prompt colour for all users.
# Sets the SSH banner (/etc/issue.net) and console login prompt (/etc/issue).
#
# Usage:
#   sudo ./apply-branding.sh --company "Acme Corp"
#   sudo ./apply-branding.sh --company "Acme Corp" --colour Cyan
#   sudo ./apply-branding.sh --company "Acme Corp" --colour Cyan --non-interactive
#
# Options:
#   --company <name>      Organisation name shown in banner and MOTD (required)
#   --colour <name>       Console text colour (default: Cyan)
#                         Choices: Red, Green, Yellow, Blue, Magenta, Cyan, White
#   --non-interactive     Skip the confirmation prompt (for automated pipelines)
#
# Author:            Darren Pilkington
# Version:           1.1
# Date:              31-05-2026
# =============================================================================

set -euo pipefail

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/system-configuration"
LOG_FILE="${LOG_DIR}/apply-branding-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── ANSI colour map ─────────────────────────────────────────────────────────
declare -A COLOUR_CODES=(
    ["Red"]="31"       ["Green"]="32"  ["Yellow"]="33" ["Blue"]="34"
    ["Magenta"]="35"   ["Cyan"]="36"   ["White"]="37"
)

# ─── Argument parsing ────────────────────────────────────────────────────────
COMPANY_NAME=""
COLOUR="Cyan"
NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --company)         COMPANY_NAME="$2"; shift 2 ;;
        --colour|--color)  COLOUR="$2";        shift 2 ;;
        --non-interactive) NON_INTERACTIVE=true; shift ;;
        --help)
            grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,2\}//'
            exit 0
            ;;
        *) fail "Unknown argument: $1. Use --help for usage." ;;
    esac
done

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]]        || fail "Run as root: sudo ./apply-branding.sh"
[[ -n "${COMPANY_NAME}" ]]   || fail "--company is required."
[[ -n "${COLOUR_CODES[${COLOUR}]+x}" ]] \
    || fail "Invalid colour '${COLOUR}'. Valid choices: ${!COLOUR_CODES[*]}"

COLOUR_CODE="${COLOUR_CODES[${COLOUR}]}"

log "Applying branding on $(hostname -f 2>/dev/null || hostname)"
log "  Company : ${COMPANY_NAME}"
log "  Colour  : ${COLOUR} (ANSI code ${COLOUR_CODE})"
log "Log file: ${LOG_FILE}"

# ─── Confirmation ────────────────────────────────────────────────────────────
if [[ "${NON_INTERACTIVE}" == false ]]; then
    read -r -p "Apply branding for '${COMPANY_NAME}'? [y/N] " CONFIRM
    [[ "${CONFIRM,,}" == "y" ]] || { log "Aborted by user."; exit 0; }
fi

# ─── Shell prompt colour for all users ──────────────────────────────────────
log "Writing console colour profile to /etc/profile.d/console-colours.sh..."
cat > /etc/profile.d/console-colours.sh <<EOF
#!/bin/sh
# Set console text colour — applied to all interactive sessions
echo -e "\\033[${COLOUR_CODE};40m"
EOF
chmod +x /etc/profile.d/console-colours.sh

log "Writing custom PS1 prompt to /etc/bash.bashrc..."
# Remove any previous branding block to avoid duplication on re-runs
sed -i '/# --- Server Branding: PS1 ---/,/# --- End Server Branding ---/d' /etc/bash.bashrc
cat >> /etc/bash.bashrc <<EOF

# --- Server Branding: PS1 ---
export PS1='\\[\\e[${COLOUR_CODE};40m\\]\\u@\\h:\\w\\\$ \\[\\e[m\\]'
# --- End Server Branding ---
EOF
log "Shell prompt configured."

# ─── SSH login banner (/etc/issue.net) ───────────────────────────────────────
log "Writing SSH login banner to /etc/issue.net..."
cat > /etc/issue.net <<EOF
Welcome to ${COMPANY_NAME}

*******************************************************************************
* WARNING: Unauthorised access to this system is prohibited and may result in *
* criminal prosecution. All activities are monitored and logged.              *
*******************************************************************************
EOF
log "SSH login banner written."

# ─── Console login prompt (/etc/issue) ───────────────────────────────────────
log "Writing console login prompt to /etc/issue..."
cat > /etc/issue <<EOF
Welcome to ${COMPANY_NAME}

*******************************************************************************
* WARNING: Unauthorised access to this system is prohibited and may result in *
* criminal prosecution. All activities are monitored and logged.              *
*******************************************************************************

\l
EOF
log "Console login prompt written."

# ─── MOTD ────────────────────────────────────────────────────────────────────
log "Writing MOTD to /etc/update-motd.d/00-header..."
cat > /etc/update-motd.d/00-header <<EOF
#!/bin/sh
printf "\\033[${COLOUR_CODE};40m"
printf "\\n"
printf "  Welcome to %s\\n" "${COMPANY_NAME}"
printf "  Hostname : \$(hostname -f 2>/dev/null || hostname)\\n"
printf "  Date     : \$(date '+%Y-%m-%d %H:%M:%S %Z')\\n"
printf "\\n"
printf "\\033[0m"
EOF
chmod +x /etc/update-motd.d/00-header

# Disable all other MOTD fragments to keep output clean
chmod -x /etc/update-motd.d/* 2>/dev/null || true
chmod +x /etc/update-motd.d/00-header
log "MOTD configured."

# ─── SSH daemon configuration ────────────────────────────────────────────────
log "Configuring SSH daemon to display banner..."
SSHD_CONFIG="/etc/ssh/sshd_config"

if grep -q "^Banner" "${SSHD_CONFIG}"; then
    sed -i 's|^Banner.*|Banner /etc/issue.net|' "${SSHD_CONFIG}"
elif grep -q "^#Banner" "${SSHD_CONFIG}"; then
    sed -i 's|^#Banner.*|Banner /etc/issue.net|' "${SSHD_CONFIG}"
else
    echo "Banner /etc/issue.net" >> "${SSHD_CONFIG}"
fi

if grep -q "^PrintMotd" "${SSHD_CONFIG}"; then
    sed -i 's|^PrintMotd.*|PrintMotd no|' "${SSHD_CONFIG}"
elif grep -q "^#PrintMotd" "${SSHD_CONFIG}"; then
    sed -i 's|^#PrintMotd.*|PrintMotd no|' "${SSHD_CONFIG}"
else
    echo "PrintMotd no" >> "${SSHD_CONFIG}"
fi
log "SSH daemon configuration updated."

# ─── Restart SSH service ─────────────────────────────────────────────────────
log "Restarting SSH service..."
if systemctl is-active --quiet ssh.service 2>/dev/null; then
    systemctl restart ssh.service
    log "ssh.service restarted."
elif systemctl is-active --quiet sshd.service 2>/dev/null; then
    systemctl restart sshd.service
    log "sshd.service restarted."
else
    warn "No active SSH service found. Banner will apply on next SSH start."
fi

log "Branding applied successfully."
log "  Company : ${COMPANY_NAME}"
log "  Colour  : ${COLOUR}"
log "  Log     : ${LOG_FILE}"
