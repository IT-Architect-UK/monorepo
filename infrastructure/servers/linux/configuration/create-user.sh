#!/usr/bin/env bash
# =============================================================================
# Create User Account — Ubuntu
# Creates a standard Linux user account with optional sudo privileges and
# optional SSH public key configuration. Safe to re-run — skips creation
# if the user already exists.
#
# Usage:
#   sudo ./create-user.sh --username <name> [--sudo] [--ssh-key "<pubkey>"]
#
# Options:
#   --username <name>   Username to create (required)
#   --sudo              Add user to the sudo group
#   --ssh-key "<key>"   Add an authorised SSH public key for the user
#
# Examples:
#   sudo ./create-user.sh --username deploy --sudo
#   sudo ./create-user.sh --username ansible --ssh-key "ssh-ed25519 AAAA... user@host"
#   sudo ./create-user.sh --username deploy --sudo --ssh-key "ssh-rsa AAAA..."
#
# Author:            Darren Pilkington
# Version:           1.1
# Date:              31-05-2026
# =============================================================================

set -euo pipefail

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/user-management"
LOG_FILE="${LOG_DIR}/create-user-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── Argument parsing ────────────────────────────────────────────────────────
USERNAME=""
ADD_SUDO=false
SSH_KEY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --username) USERNAME="$2";  shift 2 ;;
        --sudo)     ADD_SUDO=true;  shift   ;;
        --ssh-key)  SSH_KEY="$2";   shift 2 ;;
        --help)
            grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,2\}//'
            exit 0
            ;;
        *) fail "Unknown argument: $1. Use --help for usage." ;;
    esac
done

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]]    || fail "Run as root: sudo ./create-user.sh"
[[ -n "${USERNAME}" ]]   || fail "--username is required."

# Validate username: alphanumeric, hyphens, underscores only
[[ "${USERNAME}" =~ ^[a-z][a-z0-9_-]{0,30}$ ]] \
    || fail "Invalid username '${USERNAME}'. Must start with a lowercase letter, max 31 chars, a-z0-9_- only."

log "Creating user: ${USERNAME} on $(hostname -f 2>/dev/null || hostname)"
log "Log file: ${LOG_FILE}"

# ─── Create user ─────────────────────────────────────────────────────────────
if id "${USERNAME}" &>/dev/null; then
    warn "User '${USERNAME}' already exists — skipping creation."
else
    log "Creating user account '${USERNAME}'..."
    useradd \
        --create-home \
        --shell /bin/bash \
        --comment "Managed by create-user.sh" \
        "${USERNAME}"
    log "User '${USERNAME}' created."
fi

# ─── Sudo privileges ─────────────────────────────────────────────────────────
if [[ "${ADD_SUDO}" == true ]]; then
    if groups "${USERNAME}" | grep -qw sudo; then
        warn "User '${USERNAME}' is already in the sudo group."
    else
        usermod -aG sudo "${USERNAME}"
        log "User '${USERNAME}' added to the sudo group."
    fi
fi

# ─── SSH key ─────────────────────────────────────────────────────────────────
if [[ -n "${SSH_KEY}" ]]; then
    USER_HOME=$(getent passwd "${USERNAME}" | cut -d: -f6)
    SSH_DIR="${USER_HOME}/.ssh"
    AUTH_KEYS="${SSH_DIR}/authorized_keys"

    log "Configuring SSH authorised key for '${USERNAME}'..."
    mkdir -p "${SSH_DIR}"
    chmod 700 "${SSH_DIR}"
    chown "${USERNAME}:${USERNAME}" "${SSH_DIR}"

    # Only add the key if it is not already present
    if grep -qxF "${SSH_KEY}" "${AUTH_KEYS}" 2>/dev/null; then
        warn "SSH key already present in ${AUTH_KEYS} — skipping."
    else
        echo "${SSH_KEY}" >> "${AUTH_KEYS}"
        chmod 600 "${AUTH_KEYS}"
        chown "${USERNAME}:${USERNAME}" "${AUTH_KEYS}"
        log "SSH key added to ${AUTH_KEYS}."
    fi
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
log "User setup complete."
log "  Username : ${USERNAME}"
log "  Home     : $(getent passwd "${USERNAME}" | cut -d: -f6)"
log "  Shell    : $(getent passwd "${USERNAME}" | cut -d: -f7)"
log "  Sudo     : ${ADD_SUDO}"
log "  SSH key  : $( [[ -n "${SSH_KEY}" ]] && echo "configured" || echo "not set" )"
log "  Log file : ${LOG_FILE}"
log ""
log "To set a password, run: passwd ${USERNAME}"
