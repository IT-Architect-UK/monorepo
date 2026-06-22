#!/usr/bin/env bash
# =============================================================================
# setup-azure-monitor-agent.sh
# =============================================================================
# Installs the Azure Monitor Agent (AMA) on Linux VMs.
#
# What is Azure Monitor Agent?
# ─────────────────────────────
# Azure Monitor Agent is Microsoft's monitoring agent for Azure VMs. It
# replaces the older Log Analytics Agent (MMA/OMS). It collects:
#   - Performance metrics (CPU, memory, disk, network)
#   - Linux syslog events
#   - Custom log files
#   - Security events
#
# Data is sent to a Log Analytics Workspace where you can:
#   - Query logs using KQL (Kusto Query Language)
#   - Create dashboards in Azure Monitor Workbooks
#   - Set metric alerts
#   - Feed data to Microsoft Sentinel (SIEM)
#
# Prerequisites:
#   - Azure VM (or Arc-enabled on-premises server)
#   - Managed Identity enabled on the VM
#   - Log Analytics Workspace created
#
# Usage:
#   sudo ./setup-azure-monitor-agent.sh --workspace-id <ID> --workspace-key <KEY>
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

WORKSPACE_ID=""; WORKSPACE_KEY=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --workspace-id)  WORKSPACE_ID="$2";  shift 2 ;;
        --workspace-key) WORKSPACE_KEY="$2"; shift 2 ;;
        *) error "Unknown option: $1" ;;
    esac
done

[[ $EUID -ne 0 ]]          && error "Run as root: sudo $0"
[[ -z "$WORKSPACE_ID" ]]   && error "Specify --workspace-id"
[[ -z "$WORKSPACE_KEY" ]]  && error "Specify --workspace-key"

section "Azure Monitor Agent (Log Analytics) Setup"
log "Workspace ID: $WORKSPACE_ID"

section "1 — Download and Install Agent"
wget -qO /tmp/install_mma.sh \
    "https://raw.githubusercontent.com/Microsoft/OMS-Agent-for-Linux/master/installer/scripts/onboard_agent.sh"
chmod +x /tmp/install_mma.sh
/tmp/install_mma.sh -w "$WORKSPACE_ID" -s "$WORKSPACE_KEY" -d opinsights.azure.com
rm /tmp/install_mma.sh

section "2 — Verify Installation"
systemctl status omsagent@"$WORKSPACE_ID" --no-pager || warn "Agent service check inconclusive"

section "Complete!"
echo ""
log "Azure Monitor Agent installed"
echo ""
echo "  View data in Azure Portal:"
echo "  Log Analytics Workspace → Logs → Query examples"
echo ""
echo "  Example KQL query (CPU usage last hour):"
echo "  Perf | where ObjectName == 'Processor' and CounterName == '% Processor Time'"
echo "      | where TimeGenerated > ago(1h)"
echo "      | summarize avg(CounterValue) by Computer, bin(TimeGenerated, 5m)"
echo "      | render timechart"
