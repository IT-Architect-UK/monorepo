#!/usr/bin/env bash
# =============================================================================
# aws-backup-setup.sh
# =============================================================================
# Sets up AWS Backup — AWS's centralised backup service.
#
# What is AWS Backup?
# ────────────────────
# AWS Backup centrally manages backups across AWS services:
#   - EC2 (instances + EBS volumes)
#   - RDS databases
#   - DynamoDB tables
#   - EFS file systems
#   - S3 buckets
#
# This script:
#   1. Creates a Backup Vault (encrypted storage for recovery points)
#   2. Creates a Backup Plan (schedule + retention rules)
#   3. Assigns EC2 resources to the plan
#
# Prerequisites:
#   - AWS CLI installed and configured
#   - IAM permissions: backup:*, iam:CreateRole, iam:PassRole
#
# Usage:
#   ./aws-backup-setup.sh --region eu-west-2
#   ./aws-backup-setup.sh --region eu-west-2 --vault-name "prod-backups" --tag "Environment=production"
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

# ── Load defaults from .env if present ───────────────────────────────────────
ENV_FILE="$(dirname "$0")/.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE" && log "Loaded defaults from .env"


REGION="${AWS_DEFAULT_REGION:-eu-west-2}"; VAULT_NAME="default-backup-vault"
PLAN_NAME="daily-backup-plan"; TAG_KEY="Backup"; TAG_VALUE="true"

while [[ $# -gt 0 ]]; do
    case $1 in
        --region)     REGION="$2";     shift 2 ;;
        --vault-name) VAULT_NAME="$2"; shift 2 ;;
        --plan-name)  PLAN_NAME="$2";  shift 2 ;;
        --tag)        TAG="${2}"; TAG_KEY="${TAG%%=*}"; TAG_VALUE="${TAG##*=}"; shift 2 ;;
        *) error "Unknown option: $1" ;;
    esac
done

command -v aws &>/dev/null || error "AWS CLI not installed"
aws sts get-caller-identity &>/dev/null || error "AWS not authenticated. Run: aws configure"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

section "AWS Backup Setup"
log "Region     : $REGION"
log "Account    : $ACCOUNT_ID"
log "Vault      : $VAULT_NAME"
log "Resources  : All with tag $TAG_KEY=$TAG_VALUE"

section "1 — Create Backup Vault"
if aws backup describe-backup-vault --backup-vault-name "$VAULT_NAME" --region "$REGION" &>/dev/null; then
    log "Vault '$VAULT_NAME' already exists"
else
    aws backup create-backup-vault \
        --backup-vault-name "$VAULT_NAME" \
        --region "$REGION"
    log "Vault '$VAULT_NAME' created"
fi

VAULT_ARN=$(aws backup describe-backup-vault \
    --backup-vault-name "$VAULT_NAME" \
    --region "$REGION" \
    --query 'BackupVaultArn' --output text)

section "2 — Create Backup Role"
ROLE_NAME="AWSBackupDefaultRole"
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    log "IAM role '$ROLE_NAME' already exists"
else
    TRUST_POLICY='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"backup.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
    aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$TRUST_POLICY"
    aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
    aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
    log "IAM role created: $ROLE_NAME"
fi
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

section "3 — Create Backup Plan"
BACKUP_PLAN='{
  "BackupPlanName": "'"$PLAN_NAME"'",
  "Rules": [
    {
      "RuleName": "DailyBackup",
      "TargetBackupVaultName": "'"$VAULT_NAME"'",
      "ScheduleExpression": "cron(0 3 * * ? *)",
      "StartWindowMinutes": 60,
      "CompletionWindowMinutes": 180,
      "Lifecycle": {
        "DeleteAfterDays": 35
      }
    },
    {
      "RuleName": "MonthlyLongTerm",
      "TargetBackupVaultName": "'"$VAULT_NAME"'",
      "ScheduleExpression": "cron(0 3 1 * ? *)",
      "StartWindowMinutes": 60,
      "CompletionWindowMinutes": 360,
      "Lifecycle": {
        "DeleteAfterDays": 365
      }
    }
  ]
}'

PLAN_ID=$(aws backup create-backup-plan \
    --backup-plan "$BACKUP_PLAN" \
    --region "$REGION" \
    --query 'BackupPlanId' --output text 2>/dev/null || \
    aws backup list-backup-plans --region "$REGION" \
    --query "BackupPlansList[?BackupPlanName=='$PLAN_NAME'].BackupPlanId" --output text)

log "Backup plan created: $PLAN_ID"

section "4 — Assign Resources by Tag"
SELECTION='{
  "SelectionName": "TaggedResources",
  "IamRoleArn": "'"$ROLE_ARN"'",
  "ListOfTags": [
    {
      "ConditionType": "STRINGEQUALS",
      "ConditionKey": "'"$TAG_KEY"'",
      "ConditionValue": "'"$TAG_VALUE"'"
    }
  ]
}'

aws backup create-backup-selection \
    --backup-plan-id "$PLAN_ID" \
    --backup-selection "$SELECTION" \
    --region "$REGION" || warn "Selection may already exist"

log "Resources assigned: all with tag $TAG_KEY=$TAG_VALUE"

section "Complete!"
echo ""
log "AWS Backup is now configured"
echo ""
echo "  To protect an EC2 instance, add this tag:"
echo "  aws ec2 create-tags --resources <INSTANCE_ID> --tags Key=$TAG_KEY,Value=$TAG_VALUE"
echo ""
echo "  View backup jobs:"
echo "  aws backup list-backup-jobs --region $REGION"
echo ""
echo "  View recovery points (available restores):"
echo "  aws backup list-recovery-points-by-backup-vault --backup-vault-name $VAULT_NAME --region $REGION"
