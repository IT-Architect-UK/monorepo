#!/usr/bin/env bash
# =============================================================================
# Docker CE Installation — Ubuntu
# Installs Docker CE from the official Docker apt repository using the
# modern keyring method, enables the service, and adds the invoking user
# to the docker group.
#
# Usage:
#   sudo ./install-docker.sh
#
# Notes:
#   Version:           1.1
#   Author:            Darren Pilkington
#   Modification Date: 31-05-2026
# =============================================================================

set -euo pipefail

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/docker-install"
LOG_FILE="${LOG_DIR}/install-docker-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || fail "Run as root: sudo ./install-docker.sh"
command -v apt-get &>/dev/null || fail "apt-get not found — Ubuntu/Debian required."

# Capture the user who invoked sudo so we can add them to the docker group
CALLING_USER="${SUDO_USER:-$(whoami)}"
log "Installing Docker CE. Calling user: ${CALLING_USER}"
log "Log file: ${LOG_FILE}"

# ─── Remove conflicting legacy packages ──────────────────────────────────────
log "Removing conflicting legacy Docker packages..."
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do
    apt-get remove -y "${pkg}" &>/dev/null || true
done

# ─── Prerequisites ───────────────────────────────────────────────────────────
log "Installing prerequisites..."
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release

# ─── Docker GPG key ──────────────────────────────────────────────────────────
log "Adding Docker GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# ─── Docker apt repository ───────────────────────────────────────────────────
log "Adding Docker apt repository..."
DISTRO_CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu ${DISTRO_CODENAME} stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y

# ─── Install Docker ──────────────────────────────────────────────────────────
log "Installing Docker CE packages..."
apt-get install -y \
    docker-ce \
    docker-ce-cli \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# ─── Enable service ──────────────────────────────────────────────────────────
log "Enabling and starting Docker service..."
systemctl enable docker
systemctl start docker

# ─── Add user to docker group ────────────────────────────────────────────────
if id "${CALLING_USER}" &>/dev/null; then
    usermod -aG docker "${CALLING_USER}"
    log "Added '${CALLING_USER}' to the docker group."
    log "NOTE: Log out and back in (or run 'newgrp docker') for this to take effect."
fi

# ─── Verify ──────────────────────────────────────────────────────────────────
log "Verifying installation..."
docker --version        | tee -a "${LOG_FILE}"
docker compose version  | tee -a "${LOG_FILE}"

log "Docker CE installation complete."
