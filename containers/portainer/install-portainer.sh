#!/usr/bin/env bash
# =============================================================================
# Portainer CE Installation — Docker host management UI
# Deploys Portainer CE as a Docker container: web UI for managing the local
# Docker engine and any remote hosts running the Portainer Agent
# (see install-portainer-agent.sh).
#
# On the Deployment Toolbox this is baked into the image; the bootstrap
# initialises the admin account and wires the dashboard widget. Standalone,
# browse to https://<host>:9443 within 5 minutes of install to set the
# admin password (Portainer locks itself if left uninitialised).
#
# Assumes Docker CE is already installed.
#
# Usage:
#   sudo ./install-portainer.sh
#
# Author:            Darren Pilkington
# Version:           2.0
# Date:              05-07-2026
# =============================================================================

set -euo pipefail

LOG_DIR="/var/log/portainer-install"
LOG_FILE="${LOG_DIR}/install-portainer-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] || fail "Run as root: sudo ./install-portainer.sh"
command -v docker &>/dev/null || fail "Docker not found — install it first (containers/docker/install-docker.sh)"
systemctl is-active --quiet docker || fail "Docker service is not running"

CONTAINER_NAME="portainer"
IMAGE="portainer/portainer-ce:latest"

log "Installing Portainer CE on $(hostname -f 2>/dev/null || hostname)"

if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
    log "Removing existing ${CONTAINER_NAME} container (data volume is preserved)..."
    docker rm -f "${CONTAINER_NAME}" &>/dev/null || true
fi

docker volume create portainer_data >/dev/null

log "Pulling ${IMAGE}..."
docker pull "${IMAGE}" 2>&1 | tee -a "${LOG_FILE}"

log "Starting ${CONTAINER_NAME}..."
docker run -d \
    --name "${CONTAINER_NAME}" \
    -p 9443:9443 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v portainer_data:/data \
    --restart unless-stopped \
    "${IMAGE}" 2>&1 | tee -a "${LOG_FILE}"

sleep 3
docker ps --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}" \
    || fail "Portainer container did not start. Check: docker logs ${CONTAINER_NAME}"

SERVER_IP=$(hostname -I | awk '{print $1}')
log "Portainer installation complete."
log "  URL        : https://${SERVER_IP}:9443 (self-signed certificate)"
log "  First run  : set the admin password within 5 minutes (or via the API)"
log "  Agents     : add remote Docker hosts with install-portainer-agent.sh"
log "  Log file   : ${LOG_FILE}"
