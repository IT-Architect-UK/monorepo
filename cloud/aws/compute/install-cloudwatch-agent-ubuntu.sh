#!/usr/bin/env bash
# =============================================================================
# AWS CloudWatch Agent — Ubuntu Installation
# Downloads, installs, and configures the CloudWatch unified agent on Ubuntu.
# Configures collection of:
#   - System metrics (CPU, memory, disk, network)
#   - System logs (/var/log/syslog, /var/log/auth.log)
#   - Custom application log path (optional)
#
# Prerequisites:
#   - Ubuntu 20.04 / 22.04 / 24.04
#   - IAM instance profile with CloudWatchAgentServerPolicy attached, OR
#     AWS credentials set in environment variables
#
# Usage:
#   sudo ./install-cloudwatch-agent-ubuntu.sh
#   sudo ./install-cloudwatch-agent-ubuntu.sh --app-log /var/log/myapp/app.log
#   sudo ./install-cloudwatch-agent-ubuntu.sh --region us-east-1
#
# Author: IT Architect UK
# Version: 1.0
# Date: 2026-05-31
# =============================================================================

set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────
REGION="${AWS_DEFAULT_REGION:-eu-west-2}"
APP_LOG_PATH=""
LOG_DIR="/var/log/cloudwatch-agent-install"
LOG_FILE="${LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
CW_AGENT_URL="https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb"
CW_AGENT_CONFIG="/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json"

# ─── Argument parsing ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --region)   REGION="$2";       shift 2 ;;
        --app-log)  APP_LOG_PATH="$2"; shift 2 ;;
        --help)
            echo "Usage: $0 [--region <region>] [--app-log <log-path>]"
            exit 0
            ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# ─── Logging ─────────────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*"; exit 1; }

# ─── Pre-flight checks ───────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || fail "This script must be run as root."
command -v dpkg &>/dev/null || fail "This script requires a Debian-based system (dpkg not found)."

HOSTNAME_VALUE=$(hostname -f 2>/dev/null || hostname)
log "Installing CloudWatch Agent on: ${HOSTNAME_VALUE}  Region: ${REGION}"

# ─── Download and install agent ──────────────────────────────────────────────
TEMP_DEB=$(mktemp /tmp/amazon-cloudwatch-agent.XXXXXX.deb)
trap 'rm -f "${TEMP_DEB}"' EXIT

log "Downloading CloudWatch Agent..."
curl -fsSL "${CW_AGENT_URL}" -o "${TEMP_DEB}" \
    || fail "Failed to download CloudWatch Agent."

log "Installing CloudWatch Agent package..."
dpkg -i "${TEMP_DEB}" || apt-get install -f -y
log "CloudWatch Agent installed."

# ─── Build agent configuration ───────────────────────────────────────────────
log "Writing CloudWatch Agent configuration..."

# Build optional app log block
APP_LOG_BLOCK=""
if [[ -n "${APP_LOG_PATH}" ]]; then
    APP_LOG_BLOCK=$(cat <<EOF
        ,{
          "file_path": "${APP_LOG_PATH}",
          "log_group_name": "/ec2/app/$(basename "${APP_LOG_PATH}" .log)",
          "log_stream_name": "{instance_id}",
          "timestamp_format": "%Y-%m-%d %H:%M:%S"
        }
EOF
)
fi

mkdir -p "$(dirname "${CW_AGENT_CONFIG}")"

cat > "${CW_AGENT_CONFIG}" <<EOF
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root",
    "region": "${REGION}"
  },
  "metrics": {
    "namespace": "CWAgent",
    "append_dimensions": {
      "InstanceId": "\${aws:InstanceId}",
      "InstanceType": "\${aws:InstanceType}"
    },
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "metrics_collection_interval": 60,
        "totalcpu": true
      },
      "mem": {
        "measurement": ["mem_used_percent", "mem_available", "mem_total"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["used_percent", "inodes_free"],
        "metrics_collection_interval": 60,
        "resources": ["/", "/var", "/tmp"]
      },
      "net": {
        "measurement": ["bytes_sent", "bytes_recv", "packets_sent", "packets_recv"],
        "metrics_collection_interval": 60,
        "resources": ["*"]
      },
      "processes": {
        "measurement": ["running", "sleeping", "dead"]
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/syslog",
            "log_group_name": "/ec2/system/syslog",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%b %d %H:%M:%S"
          },
          {
            "file_path": "/var/log/auth.log",
            "log_group_name": "/ec2/system/auth",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%b %d %H:%M:%S"
          }${APP_LOG_BLOCK}
        ]
      }
    }
  }
}
EOF

log "Configuration written to: ${CW_AGENT_CONFIG}"

# ─── Start agent ─────────────────────────────────────────────────────────────
log "Starting CloudWatch Agent..."
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config \
    -m ec2 \
    -s \
    -c "file:${CW_AGENT_CONFIG}"

systemctl enable amazon-cloudwatch-agent
systemctl start  amazon-cloudwatch-agent

AGENT_STATUS=$(systemctl is-active amazon-cloudwatch-agent 2>/dev/null || true)
if [[ "${AGENT_STATUS}" == "active" ]]; then
    log "CloudWatch Agent is running."
else
    fail "CloudWatch Agent failed to start. Check: journalctl -u amazon-cloudwatch-agent"
fi

log "CloudWatch Agent installation complete."
log "Log file: ${LOG_FILE}"
