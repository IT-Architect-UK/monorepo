#!/usr/bin/env bash
# =============================================================================
# AWS VPC Deployment
# Creates a production-ready VPC with:
#   - Public and private subnets across two Availability Zones
#   - Internet Gateway for public subnets
#   - NAT Gateway for private subnet outbound access
#   - Separate route tables for public and private subnets
#   - VPC Flow Logs to CloudWatch
#
# Usage:
#   ./deploy-vpc.sh
#   ./deploy-vpc.sh --region eu-west-2 --cidr 10.10.0.0/16 --name prod
#   ./deploy-vpc.sh --region us-east-1 --skip-nat
#
# Author: IT Architect UK
# Version: 1.0
# Date: 2026-05-31
# =============================================================================

set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────
REGION="${AWS_DEFAULT_REGION:-eu-west-2}"
VPC_CIDR="10.0.0.0/16"
ENV_NAME="baseline"
SKIP_NAT=false
LOG_DIR="/var/log/aws-vpc"
LOG_FILE="${LOG_DIR}/deploy-vpc-$(date +%Y%m%d-%H%M%S).log"

# ─── Argument parsing ────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --region)    REGION="$2";    shift 2 ;;
        --cidr)      VPC_CIDR="$2";  shift 2 ;;
        --name)      ENV_NAME="$2";  shift 2 ;;
        --skip-nat)  SKIP_NAT=true;  shift   ;;
        --help)
            echo "Usage: $0 [--region <r>] [--cidr <cidr>] [--name <env>] [--skip-nat]"
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

tag() {
    # Helper: build --tag-specifications string for a resource type
    local resource_type="$1"
    local name="$2"
    echo "ResourceType=${resource_type},Tags=[{Key=Name,Value=${name}},{Key=Environment,Value=${ENV_NAME}}]"
}

# ─── Pre-flight ──────────────────────────────────────────────────────────────
command -v aws &>/dev/null || fail "AWS CLI not found."
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text) \
    || fail "Not authenticated. Run: aws configure"

# Derive subnet CIDRs from VPC CIDR (assumes /16 — splits into /24s)
VPC_PREFIX=$(echo "${VPC_CIDR}" | cut -d'.' -f1-2)
PUB_SUBNET_A="${VPC_PREFIX}.1.0/24"
PUB_SUBNET_B="${VPC_PREFIX}.2.0/24"
PRIV_SUBNET_A="${VPC_PREFIX}.10.0/24"
PRIV_SUBNET_B="${VPC_PREFIX}.20.0/24"

# Pick two AZs in the target region
AZ_LIST=$(aws ec2 describe-availability-zones \
    --region "${REGION}" \
    --query "AvailabilityZones[?State=='available'].ZoneName" \
    --output text)
AZ_A=$(echo "${AZ_LIST}" | awk '{print $1}')
AZ_B=$(echo "${AZ_LIST}" | awk '{print $2}')

log "Deploying VPC: ${ENV_NAME}  CIDR: ${VPC_CIDR}  Account: ${ACCOUNT_ID}  Region: ${REGION}"
log "AZs: ${AZ_A}, ${AZ_B}"

# ─── VPC ─────────────────────────────────────────────────────────────────────
log "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block "${VPC_CIDR}" \
    --region "${REGION}" \
    --tag-specifications "$(tag vpc "${ENV_NAME}-vpc")" \
    --query Vpc.VpcId --output text)

aws ec2 modify-vpc-attribute --vpc-id "${VPC_ID}" --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id "${VPC_ID}" --enable-dns-hostnames
log "VPC created: ${VPC_ID}"

# ─── Subnets ─────────────────────────────────────────────────────────────────
log "Creating subnets..."
PUB_A=$(aws ec2 create-subnet --vpc-id "${VPC_ID}" --cidr-block "${PUB_SUBNET_A}" \
    --availability-zone "${AZ_A}" \
    --tag-specifications "$(tag subnet "${ENV_NAME}-public-a")" \
    --query Subnet.SubnetId --output text)

PUB_B=$(aws ec2 create-subnet --vpc-id "${VPC_ID}" --cidr-block "${PUB_SUBNET_B}" \
    --availability-zone "${AZ_B}" \
    --tag-specifications "$(tag subnet "${ENV_NAME}-public-b")" \
    --query Subnet.SubnetId --output text)

PRIV_A=$(aws ec2 create-subnet --vpc-id "${VPC_ID}" --cidr-block "${PRIV_SUBNET_A}" \
    --availability-zone "${AZ_A}" \
    --tag-specifications "$(tag subnet "${ENV_NAME}-private-a")" \
    --query Subnet.SubnetId --output text)

PRIV_B=$(aws ec2 create-subnet --vpc-id "${VPC_ID}" --cidr-block "${PRIV_SUBNET_B}" \
    --availability-zone "${AZ_B}" \
    --tag-specifications "$(tag subnet "${ENV_NAME}-private-b")" \
    --query Subnet.SubnetId --output text)

# Enable auto-assign public IP on public subnets
aws ec2 modify-subnet-attribute --subnet-id "${PUB_A}" --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --subnet-id "${PUB_B}" --map-public-ip-on-launch
log "Subnets: Public [${PUB_A}, ${PUB_B}]  Private [${PRIV_A}, ${PRIV_B}]"

# ─── Internet Gateway ────────────────────────────────────────────────────────
log "Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications "$(tag internet-gateway "${ENV_NAME}-igw")" \
    --query InternetGateway.InternetGatewayId --output text)
aws ec2 attach-internet-gateway --internet-gateway-id "${IGW_ID}" --vpc-id "${VPC_ID}"
log "Internet Gateway: ${IGW_ID}"

# ─── Public Route Table ──────────────────────────────────────────────────────
log "Creating public route table..."
PUB_RT=$(aws ec2 create-route-table --vpc-id "${VPC_ID}" \
    --tag-specifications "$(tag route-table "${ENV_NAME}-public-rt")" \
    --query RouteTable.RouteTableId --output text)
aws ec2 create-route --route-table-id "${PUB_RT}" --destination-cidr-block 0.0.0.0/0 \
    --gateway-id "${IGW_ID}"
aws ec2 associate-route-table --route-table-id "${PUB_RT}" --subnet-id "${PUB_A}"
aws ec2 associate-route-table --route-table-id "${PUB_RT}" --subnet-id "${PUB_B}"
log "Public route table: ${PUB_RT}"

# ─── NAT Gateway + Private Route Table ──────────────────────────────────────
if [[ "${SKIP_NAT}" == false ]]; then
    log "Allocating Elastic IP and creating NAT Gateway (in ${AZ_A})..."
    EIP_ALLOC=$(aws ec2 allocate-address --domain vpc \
        --tag-specifications "$(tag elastic-ip "${ENV_NAME}-nat-eip")" \
        --query AllocationId --output text)
    NAT_GW=$(aws ec2 create-nat-gateway --subnet-id "${PUB_A}" \
        --allocation-id "${EIP_ALLOC}" \
        --tag-specifications "$(tag natgateway "${ENV_NAME}-nat-gw")" \
        --query NatGateway.NatGatewayId --output text)

    log "Waiting for NAT Gateway ${NAT_GW} to become available..."
    aws ec2 wait nat-gateway-available --nat-gateway-ids "${NAT_GW}"
    log "NAT Gateway ready: ${NAT_GW}"

    PRIV_RT=$(aws ec2 create-route-table --vpc-id "${VPC_ID}" \
        --tag-specifications "$(tag route-table "${ENV_NAME}-private-rt")" \
        --query RouteTable.RouteTableId --output text)
    aws ec2 create-route --route-table-id "${PRIV_RT}" --destination-cidr-block 0.0.0.0/0 \
        --nat-gateway-id "${NAT_GW}"
    aws ec2 associate-route-table --route-table-id "${PRIV_RT}" --subnet-id "${PRIV_A}"
    aws ec2 associate-route-table --route-table-id "${PRIV_RT}" --subnet-id "${PRIV_B}"
    log "Private route table: ${PRIV_RT}"
else
    log "Skipping NAT Gateway (--skip-nat set)."
fi

# ─── VPC Flow Logs ───────────────────────────────────────────────────────────
log "Enabling VPC Flow Logs to CloudWatch..."
LOG_GROUP="/aws/vpc/flowlogs/${ENV_NAME}"
aws logs create-log-group --log-group-name "${LOG_GROUP}" --region "${REGION}" 2>/dev/null || true

# IAM role for flow logs (requires pre-existing or manual creation if permissions absent)
FLOW_LOG_ROLE="arn:aws:iam::${ACCOUNT_ID}:role/vpc-flow-logs-role"
aws ec2 create-flow-logs \
    --resource-type VPC \
    --resource-ids "${VPC_ID}" \
    --traffic-type ALL \
    --log-destination-type cloud-watch-logs \
    --log-group-name "${LOG_GROUP}" \
    --deliver-logs-permission-arn "${FLOW_LOG_ROLE}" 2>/dev/null \
    && log "VPC Flow Logs enabled to CloudWatch log group: ${LOG_GROUP}" \
    || warn "Could not enable Flow Logs — ensure vpc-flow-logs-role IAM role exists."

# ─── Summary ─────────────────────────────────────────────────────────────────
log ""
log "VPC Deployment Complete"
log "  VPC ID          : ${VPC_ID}"
log "  CIDR            : ${VPC_CIDR}"
log "  Public subnets  : ${PUB_A} (${AZ_A}), ${PUB_B} (${AZ_B})"
log "  Private subnets : ${PRIV_A} (${AZ_A}), ${PRIV_B} (${AZ_B})"
log "  Internet GW     : ${IGW_ID}"
[[ "${SKIP_NAT}" == false ]] && log "  NAT Gateway     : ${NAT_GW}"
log "  Log file        : ${LOG_FILE}"
