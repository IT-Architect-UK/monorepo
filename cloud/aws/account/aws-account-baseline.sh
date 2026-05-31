#!/usr/bin/env bash
# =============================================================================
# AWS Account Baseline Hardening
# Applies security best-practice baseline configuration to a new AWS account:
#   - CloudTrail multi-region trail with S3 logging
#   - GuardDuty threat detection
#   - AWS Config recording
#   - S3 Block Public Access at account level
#   - IAM password policy enforcement
#   - Default VPC removal (optional)
#
# Prerequisites:
#   - AWS CLI v2 installed and configured (aws configure)
#   - IAM permissions: CloudTrail:*, GuardDuty:*, config:*, s3:*, iam:*
#
# Usage:
#   ./aws-account-baseline.sh
#   ./aws-account-baseline.sh --region eu-west-2 --skip-delete-default-vpc
#
# Author: IT Architect UK
# Version: 1.0
# Date: 2026-05-31
# =============================================================================

set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────
REGION="${AWS_DEFAULT_REGION:-eu-west-2}"
SKIP_DELETE_DEFAULT_VPC=false
LOG_DIR="/var/log/aws-baseline"
LOG_FILE="${LOG_DIR}/aws-baseline-$(date +%Y%m%d-%H%M%S).log"

# ─── Argument parsing ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --region)                   REGION="$2";               shift 2 ;;
        --skip-delete-default-vpc)  SKIP_DELETE_DEFAULT_VPC=true; shift ;;
        --help)
            echo "Usage: $0 [--region <region>] [--skip-delete-default-vpc]"
            exit 0
            ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

# ─── Logging ─────────────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*"; exit 1; }

# ─── Pre-flight checks ───────────────────────────────────────────────────────
command -v aws &>/dev/null || fail "AWS CLI not found. Install from: https://aws.amazon.com/cli/"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
    || fail "AWS CLI not authenticated. Run: aws configure"

log "AWS Account Baseline — Account: ${ACCOUNT_ID}  Region: ${REGION}"
log "Log file: ${LOG_FILE}"

# ─── IAM Password Policy ─────────────────────────────────────────────────────
log "Applying IAM password policy..."
aws iam update-account-password-policy \
    --minimum-password-length 14 \
    --require-symbols \
    --require-numbers \
    --require-uppercase-characters \
    --require-lowercase-characters \
    --allow-users-to-change-password \
    --max-password-age 90 \
    --password-reuse-prevention 12 \
    --hard-expiry
log "IAM password policy applied."

# ─── S3 Block Public Access (account level) ──────────────────────────────────
log "Enabling S3 Block Public Access at account level..."
aws s3control put-public-access-block \
    --account-id "${ACCOUNT_ID}" \
    --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
log "S3 Block Public Access enabled."

# ─── CloudTrail ──────────────────────────────────────────────────────────────
TRAIL_BUCKET="aws-cloudtrail-logs-${ACCOUNT_ID}-${REGION}"
TRAIL_NAME="aws-baseline-trail"

log "Creating CloudTrail S3 bucket: ${TRAIL_BUCKET}..."
if ! aws s3api head-bucket --bucket "${TRAIL_BUCKET}" 2>/dev/null; then
    aws s3api create-bucket \
        --bucket "${TRAIL_BUCKET}" \
        --region "${REGION}" \
        --create-bucket-configuration LocationConstraint="${REGION}"

    aws s3api put-bucket-versioning \
        --bucket "${TRAIL_BUCKET}" \
        --versioning-configuration Status=Enabled

    aws s3api put-public-access-block \
        --bucket "${TRAIL_BUCKET}" \
        --public-access-block-configuration \
            BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

    BUCKET_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSCloudTrailAclCheck",
      "Effect": "Allow",
      "Principal": {"Service": "cloudtrail.amazonaws.com"},
      "Action": "s3:GetBucketAcl",
      "Resource": "arn:aws:s3:::${TRAIL_BUCKET}"
    },
    {
      "Sid": "AWSCloudTrailWrite",
      "Effect": "Allow",
      "Principal": {"Service": "cloudtrail.amazonaws.com"},
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::${TRAIL_BUCKET}/AWSLogs/${ACCOUNT_ID}/*",
      "Condition": {"StringEquals": {"s3:x-amz-acl": "bucket-owner-full-control"}}
    }
  ]
}
EOF
)
    aws s3api put-bucket-policy --bucket "${TRAIL_BUCKET}" --policy "${BUCKET_POLICY}"
    log "CloudTrail bucket created and configured."
else
    log "CloudTrail bucket already exists — skipping creation."
fi

log "Creating multi-region CloudTrail trail: ${TRAIL_NAME}..."
if ! aws cloudtrail describe-trails --trail-name-list "${TRAIL_NAME}" \
    --query "trailList[0].TrailARN" --output text 2>/dev/null | grep -q "arn:"; then
    aws cloudtrail create-trail \
        --name "${TRAIL_NAME}" \
        --s3-bucket-name "${TRAIL_BUCKET}" \
        --is-multi-region-trail \
        --enable-log-file-validation
    aws cloudtrail start-logging --name "${TRAIL_NAME}"
    log "CloudTrail trail created and logging started."
else
    log "CloudTrail trail '${TRAIL_NAME}' already exists — skipping."
fi

# ─── GuardDuty ───────────────────────────────────────────────────────────────
log "Enabling GuardDuty..."
DETECTOR_ID=$(aws guardduty list-detectors --region "${REGION}" \
    --query detectorIds[0] --output text 2>/dev/null)

if [[ -z "${DETECTOR_ID}" || "${DETECTOR_ID}" == "None" ]]; then
    DETECTOR_ID=$(aws guardduty create-detector \
        --enable \
        --finding-publishing-frequency SIX_HOURS \
        --region "${REGION}" \
        --query DetectorId --output text)
    log "GuardDuty enabled. Detector ID: ${DETECTOR_ID}"
else
    log "GuardDuty already enabled. Detector ID: ${DETECTOR_ID}"
fi

# ─── AWS Config ──────────────────────────────────────────────────────────────
log "Checking AWS Config recorder status..."
RECORDER_STATUS=$(aws configservice describe-configuration-recorders \
    --query "ConfigurationRecorders[0].name" --output text 2>/dev/null || true)

if [[ -z "${RECORDER_STATUS}" || "${RECORDER_STATUS}" == "None" ]]; then
    log "AWS Config not configured — manual setup recommended (requires SNS topic and Config role)."
    warn "Skipping AWS Config setup — run aws configservice put-configuration-recorder manually."
else
    log "AWS Config already configured: ${RECORDER_STATUS}"
fi

# ─── Default VPC removal ─────────────────────────────────────────────────────
if [[ "${SKIP_DELETE_DEFAULT_VPC}" == false ]]; then
    log "Removing default VPC in region ${REGION}..."
    DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=isDefault,Values=true" \
        --query "Vpcs[0].VpcId" \
        --output text 2>/dev/null)

    if [[ -n "${DEFAULT_VPC_ID}" && "${DEFAULT_VPC_ID}" != "None" ]]; then
        # Delete internet gateways attached to default VPC
        IGW_IDS=$(aws ec2 describe-internet-gateways \
            --filters "Name=attachment.vpc-id,Values=${DEFAULT_VPC_ID}" \
            --query "InternetGateways[*].InternetGatewayId" \
            --output text)
        for IGW_ID in ${IGW_IDS}; do
            aws ec2 detach-internet-gateway --internet-gateway-id "${IGW_ID}" --vpc-id "${DEFAULT_VPC_ID}"
            aws ec2 delete-internet-gateway --internet-gateway-id "${IGW_ID}"
        done

        # Delete default subnets
        SUBNET_IDS=$(aws ec2 describe-subnets \
            --filters "Name=vpc-id,Values=${DEFAULT_VPC_ID}" \
            --query "Subnets[*].SubnetId" \
            --output text)
        for SUBNET_ID in ${SUBNET_IDS}; do
            aws ec2 delete-subnet --subnet-id "${SUBNET_ID}"
        done

        aws ec2 delete-vpc --vpc-id "${DEFAULT_VPC_ID}"
        log "Default VPC ${DEFAULT_VPC_ID} deleted."
    else
        log "No default VPC found in ${REGION} — nothing to delete."
    fi
else
    log "Skipping default VPC deletion (--skip-delete-default-vpc set)."
fi

log "AWS Account Baseline complete for account ${ACCOUNT_ID} in ${REGION}."
log "Review log: ${LOG_FILE}"
