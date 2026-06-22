#!/usr/bin/env bash
# =============================================================================
# setup-gcp-ops-agent.sh
# =============================================================================
# Installs the Google Cloud Ops Agent on Linux VMs.
#
# What is the Ops Agent?
# ──────────────────────
# The Ops Agent is GCP's unified monitoring and logging agent. It replaces
# the older Stackdriver Monitoring and Logging agents. It collects:
#   - System metrics: CPU, memory, disk, network, process counts
#   - Application metrics: Nginx, Apache, MySQL, Redis, PostgreSQL, and more
#   - Log files: syslog, nginx access logs, custom application logs
#
# Data goes to:
#   - Cloud Monitoring (metrics, dashboards, alerting)
#   - Cloud Logging (log search, log-based metrics, log exports)
#
# Prerequisites:
#   - GCP Compute Engine VM
#   - IAM: roles/monitoring.metricWriter + roles/logging.logWriter on the instance
#   - (These are included by default if using the default compute service account)
#
# Usage:
#   sudo ./setup-gcp-ops-agent.sh
#
# Author  : IT-Architect-UK
# Repo    : https://github.com/IT-Architect-UK/monorepo
# Version : 1.0.0
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
log()     { echo -e "${GREEN}[✔]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✘] ERROR:${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BLUE}${BOLD}━━━ $* ━━━${NC}"; }

[[ $EUID -ne 0 ]] && error "Run as root: sudo $0"

section "GCP Ops Agent Installation"

section "1 — Install Ops Agent"
curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
bash add-google-cloud-ops-agent-repo.sh --also-install
rm add-google-cloud-ops-agent-repo.sh
log "Ops Agent installed"

section "2 — Verify Service"
systemctl is-active google-cloud-ops-agent && log "Ops Agent is running" || warn "Ops Agent may still be starting"

section "3 — Check Agent Version"
google_cloud_ops_agent_engine --version 2>/dev/null || true

section "Complete!"
echo ""
log "GCP Ops Agent is now running"
echo ""
echo "  View metrics in GCP Console:"
echo "  Cloud Monitoring → Metrics Explorer → VM Instance → memory/percent_used"
echo ""
echo "  View logs:"
echo "  Cloud Logging → Logs Explorer → resource.type='gce_instance'"
echo ""
echo "  Create an alerting policy (example: disk > 90%):"
echo "  gcloud alpha monitoring policies create \\"
echo "    --notification-channels=<CHANNEL_ID> \\"
echo "    --display-name='Disk High' \\"
echo "    --condition-display-name='Disk > 90%' \\"
echo "    --condition-filter='metric.type=\"agent.googleapis.com/disk/percent_used\" AND metric.labels.state=\"used\"' \\"
echo "    --condition-threshold-value=90 \\"
echo "    --condition-threshold-comparison=COMPARISON_GT"
