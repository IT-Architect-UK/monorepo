#!/usr/bin/env bash
# =============================================================================
# build-golden-ami.sh
# =============================================================================
# Builds a "golden" Amazon Machine Image (AMI) — a pre-patched, configured
# EC2 image that you can use to launch new instances quickly.
#
# What is an AMI?
# ───────────────
# An AMI is the AWS equivalent of a VMware template or Proxmox cloud-init image.
# Every EC2 instance is launched from an AMI. By creating your own AMI, you
# control exactly what software and configuration is included.
#
# What this script does:
#   1. Launches a temporary EC2 instance from a base Ubuntu AMI
#   2. Applies OS patches and installs standard tools via SSM Run Command
#   3. Waits for the instance to be ready
#   4. Creates an AMI (snapshot of the instance)
#   5. Terminates the source instance
#   6. Tags the AMI with creation date
#
# Prerequisites:
#   - AWS CLI installed and configured
#   - IAM permissions: ec2:*, ssm:SendCommand
#   - A VPC with a public subnet (or SSM endpoint for private)
#
# Usage:
#   ./build-golden-ami.sh --region eu-west-2
#   ./build-golden-ami.sh --region eu-west-2 --instance-type t3.medium --name "ubuntu-2404-golden"
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

REGION="eu-west-2"; INSTANCE_TYPE="t3.micro"; AMI_NAME="ubuntu-2404-golden"
SUBNET_ID=""; KEY_NAME=""; SG_ID=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --region)        REGION="$2";        shift 2 ;;
        --instance-type) INSTANCE_TYPE="$2"; shift 2 ;;
        --name)          AMI_NAME="$2";      shift 2 ;;
        --subnet-id)     SUBNET_ID="$2";     shift 2 ;;
        --key-name)      KEY_NAME="$2";      shift 2 ;;
        --sg-id)         SG_ID="$2";         shift 2 ;;
        *) error "Unknown option: $1" ;;
    esac
done

command -v aws &>/dev/null || error "AWS CLI not installed"
aws sts get-caller-identity &>/dev/null || error "Not authenticated"

section "Building Golden AMI: $AMI_NAME"
log "Region: $REGION | Instance type: $INSTANCE_TYPE"

section "1 — Find Latest Ubuntu 24.04 AMI"
BASE_AMI=$(aws ec2 describe-images \
    --owners 099720109477 \
    --filters \
        "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
        "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text \
    --region "$REGION")
log "Base AMI: $BASE_AMI"

section "2 — Launch Temporary Instance"
LAUNCH_ARGS=(
    --image-id "$BASE_AMI"
    --instance-type "$INSTANCE_TYPE"
    --region "$REGION"
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ami-builder-temp},{Key=Purpose,Value=GoldenAMIBuild}]'
    --metadata-options "HttpTokens=required"
    --iam-instance-profile "Name=EC2-SSM-Role"
)
[[ -n "$SUBNET_ID" ]] && LAUNCH_ARGS+=(--subnet-id "$SUBNET_ID")
[[ -n "$KEY_NAME" ]]  && LAUNCH_ARGS+=(--key-name "$KEY_NAME")
[[ -n "$SG_ID" ]]     && LAUNCH_ARGS+=(--security-group-ids "$SG_ID")

INSTANCE_ID=$(aws ec2 run-instances "${LAUNCH_ARGS[@]}" \
    --query 'Instances[0].InstanceId' --output text)
log "Launched instance: $INSTANCE_ID"

# Wait for running
log "Waiting for instance to enter running state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

# Wait for SSM agent
log "Waiting for SSM agent (up to 5 minutes)..."
for i in $(seq 1 30); do
    STATUS=$(aws ssm describe-instance-information \
        --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
        --query 'InstanceInformationList[0].PingStatus' --output text --region "$REGION" 2>/dev/null || echo "None")
    [[ "$STATUS" == "Online" ]] && break
    sleep 10
done
log "SSM agent is online"

section "3 — Apply Updates via SSM"
CMD_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["apt-get update -q","DEBIAN_FRONTEND=noninteractive apt-get upgrade -y","apt-get autoremove -y","apt-get clean","apt-get install -y curl wget git vim jq awscli"]' \
    --region "$REGION" \
    --query 'Command.CommandId' --output text)

log "Waiting for updates to complete (Command: $CMD_ID)..."
aws ssm wait command-executed \
    --command-id "$CMD_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION"
log "Updates applied"

section "4 — Create AMI"
TIMESTAMP=$(date +%Y%m%d-%H%M)
FULL_AMI_NAME="${AMI_NAME}-${TIMESTAMP}"

AMI_ID=$(aws ec2 create-image \
    --instance-id "$INSTANCE_ID" \
    --name "$FULL_AMI_NAME" \
    --description "Golden AMI — Ubuntu 24.04 LTS — Built $(date)" \
    --no-reboot \
    --region "$REGION" \
    --query 'ImageId' --output text)

log "Creating AMI: $AMI_ID ($FULL_AMI_NAME)"
log "Waiting for AMI to become available (5-15 minutes)..."
aws ec2 wait image-available --image-ids "$AMI_ID" --region "$REGION"
log "AMI is available"

section "5 — Tag AMI"
aws ec2 create-tags --resources "$AMI_ID" --region "$REGION" --tags \
    "Key=Name,Value=$FULL_AMI_NAME" \
    "Key=CreatedDate,Value=$(date +%Y-%m-%d)" \
    "Key=SourceAMI,Value=$BASE_AMI" \
    "Key=Purpose,Value=GoldenImage"
log "AMI tagged"

section "6 — Terminate Source Instance"
aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$REGION" | Out-Null 2>/dev/null || true
log "Source instance terminated: $INSTANCE_ID"

section "Complete!"
echo ""
log "Golden AMI created:"
log "  ID   : $AMI_ID"
log "  Name : $FULL_AMI_NAME"
echo ""
echo "  Use this AMI to launch pre-patched EC2 instances:"
echo "  aws ec2 run-instances --image-id $AMI_ID --instance-type t3.medium --region $REGION"
echo ""
echo "  Recommended: run this script monthly for a fresh golden image"
