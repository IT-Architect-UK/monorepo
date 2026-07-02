#!/usr/bin/env bash
# =============================================================================
# Homepage Dashboard Installation — Deployment Toolbox
# Deploys Homepage (gethomepage.dev) as a Docker container: a single-page
# status dashboard and launcher for the toolbox's management interfaces
# (Foreman, Vault, Prometheus, Grafana, Portainer, Webmin, Proxmox).
#
# Live status widgets are available out of the box for Grafana, Portainer,
# Prometheus, and Proxmox. Everything else (Foreman, Vault, Webmin) gets a
# bookmark tile with a Docker-based up/down indicator, since no purpose-built
# widget exists for them.
#
# Assumes Docker CE is already installed (it is, as part of the toolbox
# golden image) — this script does not install Docker itself.
#
# Usage:
#   sudo ./install-homepage.sh
#
# Author:            Darren Pilkington
# Version:           1.0
# Date:              02-07-2026
# =============================================================================

set -euo pipefail

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/homepage-install"
LOG_FILE="${LOG_DIR}/install-homepage-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || fail "Run as root: sudo ./install-homepage.sh"
command -v docker &>/dev/null || fail "Docker not found. This script assumes Docker CE is already installed on the toolbox VM."
systemctl is-active --quiet docker || fail "Docker service is not running. Start it first: systemctl start docker"

log "Installing Homepage dashboard on $(hostname -f 2>/dev/null || hostname)"
log "Log file: ${LOG_FILE}"

CONFIG_DIR="/opt/homepage/config"
ENV_FILE="/opt/homepage/.env.homepage"
CONTAINER_NAME="homepage"
IMAGE="ghcr.io/gethomepage/homepage:latest"
HOST_PORT="3000"

# ─── Clean up any previous install ──────────────────────────────────────────
if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
    log "Removing existing ${CONTAINER_NAME} container..."
    docker rm -f "${CONTAINER_NAME}" &>/dev/null || true
fi

mkdir -p "${CONFIG_DIR}"

# ─── Write services.yaml ─────────────────────────────────────────────────────
# Placeholder hostnames/ports throughout -- update once each tool is actually
# deployed. Credentials are never written here: they resolve at container
# runtime from HOMEPAGE_VAR_* env vars (see .env.homepage below), so this
# file is safe to keep under version control as-is.
if [[ ! -f "${CONFIG_DIR}/services.yaml" ]]; then
    log "Writing services.yaml (first install — edit in place on future runs, this script won't overwrite it)..."
    cat > "${CONFIG_DIR}/services.yaml" <<'YAML_EOF'
- Core Console:
    - Foreman:
        icon: foreman.png
        href: https://toolbox.lab.local/
        description: VM & bare-metal provisioning, inventory, job execution

- Secrets & Monitoring:
    - Vault:
        icon: vault.png
        href: https://toolbox.lab.local:8200/
        description: Secrets management

    - Prometheus:
        icon: prometheus.png
        href: http://toolbox.lab.local:9090/
        description: Metrics collection
        widget:
          type: prometheus
          url: http://toolbox.lab.local:9090

    - Grafana:
        icon: grafana.png
        href: http://toolbox.lab.local:3001/
        description: Monitoring dashboards
        widget:
          type: grafana
          url: http://toolbox.lab.local:3001
          username: "{{HOMEPAGE_VAR_GRAFANA_USER}}"
          password: "{{HOMEPAGE_VAR_GRAFANA_PASS}}"

- Container Management:
    - Portainer:
        icon: portainer.png
        href: https://toolbox.lab.local:9443/
        description: Docker/container fleet management
        widget:
          type: portainer
          url: https://toolbox.lab.local:9443
          env: 1
          key: "{{HOMEPAGE_VAR_PORTAINER_KEY}}"

- Admin:
    - Webmin:
        icon: webmin.png
        href: https://toolbox.lab.local:10000/
        description: General server administration

    - Proxmox Host:
        icon: proxmox.png
        href: https://192.168.4.150:8006/
        description: POSVMPWS01 hypervisor
        widget:
          type: proxmox
          url: https://192.168.4.150:8006
          username: "{{HOMEPAGE_VAR_PROXMOX_USER}}"
          password: "{{HOMEPAGE_VAR_PROXMOX_PASS}}"
YAML_EOF
else
    log "services.yaml already exists — leaving it untouched."
fi

# ─── Write settings.yaml ──────────────────────────────────────────────────────
if [[ ! -f "${CONFIG_DIR}/settings.yaml" ]]; then
    log "Writing settings.yaml..."
    cat > "${CONFIG_DIR}/settings.yaml" <<'YAML_EOF'
title: Deployment Toolbox
theme: dark
color: slate
statusStyle: dot
YAML_EOF
else
    log "settings.yaml already exists — leaving it untouched."
fi

# ─── Env file for widget credentials ─────────────────────────────────────────
# Never contains real values here. Real credentials belong here only on the
# live server, and this path is never committed to git.
if [[ ! -f "${ENV_FILE}" ]]; then
    warn "${ENV_FILE} not found — creating a placeholder. Widgets needing credentials"
    warn "(Grafana, Portainer, Proxmox) will show errors until you fill in real values"
    warn "and re-run: docker restart ${CONTAINER_NAME}"
    cat > "${ENV_FILE}" <<'ENV_EOF'
# Homepage widget credentials -- fill in real values, then: docker restart homepage
# Never commit this file.
HOMEPAGE_VAR_GRAFANA_USER=
HOMEPAGE_VAR_GRAFANA_PASS=
HOMEPAGE_VAR_PORTAINER_KEY=
HOMEPAGE_VAR_PROXMOX_USER=
HOMEPAGE_VAR_PROXMOX_PASS=
ENV_EOF
    chmod 600 "${ENV_FILE}"
else
    log "${ENV_FILE} already exists — leaving it untouched."
fi

# ─── Run container ───────────────────────────────────────────────────────────
log "Pulling ${IMAGE}..."
docker pull "${IMAGE}" 2>&1 | tee -a "${LOG_FILE}"

log "Starting ${CONTAINER_NAME}..."
docker run -d \
    --name "${CONTAINER_NAME}" \
    -p "${HOST_PORT}:3000" \
    -v "${CONFIG_DIR}:/app/config" \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    --env-file "${ENV_FILE}" \
    --restart unless-stopped \
    "${IMAGE}" 2>&1 | tee -a "${LOG_FILE}"

# ─── Verify ──────────────────────────────────────────────────────────────────
sleep 3
if docker ps --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
    log "Homepage container is running."
else
    fail "Homepage container did not start. Check: docker logs ${CONTAINER_NAME}"
fi

SERVER_IP=$(hostname -I | awk '{print $1}')

log "Homepage installation complete."
log "  URL         : http://${SERVER_IP}:${HOST_PORT}"
log "  Config dir  : ${CONFIG_DIR}"
log "  Credentials : ${ENV_FILE} (edit, then: docker restart ${CONTAINER_NAME})"
log "  Log file    : ${LOG_FILE}"
