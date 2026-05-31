#!/usr/bin/env bash
# =============================================================================
# Grafana + Prometheus Installation — Ubuntu (Bare-Metal)
# Installs the latest Prometheus release from GitHub and Grafana OSS from the
# official apt repository. Both run as systemd services.
#
# Usage:
#   sudo ./install-grafana-prometheus.sh
#   sudo ./install-grafana-prometheus.sh --prometheus-version 2.52.0
#
# Notes:
#   Version:           1.1
#   Author:            Darren Pilkington
#   Modification Date: 31-05-2026
# =============================================================================

set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────
PROMETHEUS_VERSION="${PROMETHEUS_VERSION:-latest}"

# ─── Argument parsing ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prometheus-version) PROMETHEUS_VERSION="$2"; shift 2 ;;
        --help) echo "Usage: $0 [--prometheus-version <x.y.z>]"; exit 0 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/grafana-prometheus-install"
LOG_FILE="${LOG_DIR}/install-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || fail "Run as root: sudo ./install-grafana-prometheus.sh"
command -v curl &>/dev/null || apt-get install -y curl
log "Log file: ${LOG_FILE}"

# ─── Resolve latest Prometheus version from GitHub ───────────────────────────
if [[ "${PROMETHEUS_VERSION}" == "latest" ]]; then
    log "Resolving latest Prometheus version from GitHub..."
    PROMETHEUS_VERSION=$(curl -fsSL \
        https://api.github.com/repos/prometheus/prometheus/releases/latest \
        | grep '"tag_name"' | head -1 | sed 's/.*"v\([^"]*\)".*/\1/')
    [[ -n "${PROMETHEUS_VERSION}" ]] || fail "Could not determine latest Prometheus version."
fi
log "Prometheus version: ${PROMETHEUS_VERSION}"

# ─── System update ───────────────────────────────────────────────────────────
log "Updating package lists..."
apt-get update -y
apt-get install -y software-properties-common curl wget gnupg

# ─── Prometheus ──────────────────────────────────────────────────────────────
log "Creating prometheus user..."
id prometheus &>/dev/null || useradd --no-create-home --shell /bin/false prometheus

log "Creating Prometheus directories..."
mkdir -p /etc/prometheus /var/lib/prometheus
chown prometheus:prometheus /etc/prometheus /var/lib/prometheus

PROM_ARCHIVE="prometheus-${PROMETHEUS_VERSION}.linux-amd64"
PROM_URL="https://github.com/prometheus/prometheus/releases/download/v${PROMETHEUS_VERSION}/${PROM_ARCHIVE}.tar.gz"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "${WORK_DIR}"' EXIT

log "Downloading Prometheus ${PROMETHEUS_VERSION}..."
curl -fsSL "${PROM_URL}" -o "${WORK_DIR}/${PROM_ARCHIVE}.tar.gz"
tar -xzf "${WORK_DIR}/${PROM_ARCHIVE}.tar.gz" -C "${WORK_DIR}"

cp "${WORK_DIR}/${PROM_ARCHIVE}/prometheus"  /usr/local/bin/
cp "${WORK_DIR}/${PROM_ARCHIVE}/promtool"    /usr/local/bin/
chown prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool

cp -r "${WORK_DIR}/${PROM_ARCHIVE}/consoles"          /etc/prometheus/
cp -r "${WORK_DIR}/${PROM_ARCHIVE}/console_libraries" /etc/prometheus/
chown -R prometheus:prometheus /etc/prometheus/consoles /etc/prometheus/console_libraries

log "Writing Prometheus configuration..."
cat > /etc/prometheus/prometheus.yml <<'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'node'
    static_configs:
      - targets: ['localhost:9100']
EOF
chown prometheus:prometheus /etc/prometheus/prometheus.yml

log "Creating Prometheus systemd service..."
cat > /etc/systemd/system/prometheus.service <<'EOF'
[Unit]
Description=Prometheus Monitoring
Wants=network-online.target
After=network-online.target

[Service]
User=prometheus
Group=prometheus
Type=simple
Restart=on-failure
ExecStart=/usr/local/bin/prometheus \
    --config.file=/etc/prometheus/prometheus.yml \
    --storage.tsdb.path=/var/lib/prometheus/ \
    --storage.tsdb.retention.time=30d \
    --web.console.templates=/etc/prometheus/consoles \
    --web.console.libraries=/etc/prometheus/console_libraries \
    --web.listen-address=0.0.0.0:9090

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable prometheus
systemctl start prometheus
log "Prometheus service started."

# ─── Grafana ─────────────────────────────────────────────────────────────────
log "Installing Grafana OSS..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
    | tee /etc/apt/sources.list.d/grafana.list > /dev/null
apt-get update -y
apt-get install -y grafana

systemctl daemon-reload
systemctl enable grafana-server
systemctl start grafana-server
log "Grafana service started."

# ─── Verify ──────────────────────────────────────────────────────────────────
log "Verifying services..."
systemctl is-active prometheus  | tee -a "${LOG_FILE}"
systemctl is-active grafana-server | tee -a "${LOG_FILE}"

log "Installation complete."
log "  Prometheus : http://$(hostname -I | awk '{print $1}'):9090"
log "  Grafana    : http://$(hostname -I | awk '{print $1}'):3000  (admin/admin)"
