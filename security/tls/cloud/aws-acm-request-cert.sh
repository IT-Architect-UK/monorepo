#!/usr/bin/env bash
# =============================================================================
# aws-acm-request-cert.sh
# =============================================================================
# Requests a free TLS certificate from AWS Certificate Manager (ACM).
#
# What is ACM?
# ────────────
# AWS Certificate Manager is AWS's equivalent of Let's Encrypt. It provides
# free, auto-renewing TLS certificates that attach directly to AWS services:
#   - Application Load Balancers (ALB)
#   - CloudFront distributions
#   - API Gateway
#   - Elastic Beanstalk
#
# IMPORTANT: ACM certificates cannot be downloaded or used on non-AWS servers.
# Use Let's Encrypt (install-certbot-nginx.sh) for self-managed servers.
#
# Validation methods:
#   DNS validation  (recommended) — Add a CNAME record to your DNS zone.
#                                    Automatic renewal never requires action again.
#   Email validation — ACM emails the domain owner. Simpler but needs manual renewal.
#
# Prerequisites:
#   - AWS CLI installed and configured: aws configure
#   - Permissions: acm:RequestCertificate, acm:DescribeCertificate
#   - Access to update DNS records for your domain
#
# Usage:
#   ./aws-acm-request-cert.sh -d example.com -r us-east-1
#   ./aws-acm-request-cert.sh -d example.com -d www.example.com -d api.example.com -r eu-west-2
#
# Options:
#   -d DOMAIN    Domain name (repeat for additional SANs)
#   -r REGION    AWS region (default: us-east-1; CloudFront requires us-east-1)
#   -v METHOD    Validation method: DNS or EMAIL (default: DNS)
#   -t TAG       Optional: tags in key=value format (can repeat)
#   -h           Help
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
ENV_FILE="$(dirname "$0")/../.env"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE" && log "Loaded defaults from .env"


DOMAINS=(); REGION="${AWS_DEFAULT_REGION:-us-east-1}"; VALIDATION="DNS"; TAGS=()

while getopts "d:r:v:t:h" opt; do
    case $opt in
        d) DOMAINS+=("$OPTARG") ;;
        r) REGION="$OPTARG" ;;
        v) VALIDATION="${OPTARG^^}" ;;
        t) TAGS+=("$OPTARG") ;;
        h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) error "Unknown option. Use -h for help." ;;
    esac
done

[[ ${#DOMAINS[@]} -eq 0 ]] && error "Specify at least one domain with -d"
command -v aws &>/dev/null       || error "AWS CLI not installed. See: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html"
aws sts get-caller-identity &>/dev/null || error "AWS credentials not configured. Run: aws configure"

PRIMARY="${DOMAINS[0]}"

section "AWS Certificate Manager — Request Certificate"
log "Domain(s)  : ${DOMAINS[*]}"
log "Region     : $REGION"
log "Validation : $VALIDATION"

# Build SANs argument (Subject Alternative Names — additional domains on same cert)
SAN_ARGS=""
if [[ ${#DOMAINS[@]} -gt 1 ]]; then
    SAN_ARGS="--subject-alternative-names"
    for d in "${DOMAINS[@]:1}"; do SAN_ARGS+=" $d"; done
fi

# Build tags argument
TAG_ARGS=""
if [[ ${#TAGS[@]} -gt 0 ]]; then
    TAG_LIST=""
    for t in "${TAGS[@]}"; do
        KEY="${t%%=*}"; VAL="${t##*=}"
        TAG_LIST+="Key=${KEY},Value=${VAL} "
    done
    TAG_ARGS="--tags $TAG_LIST"
fi

section "1 — Request Certificate"
log "Submitting certificate request to ACM..."

CERT_ARN=$(aws acm request-certificate \
    --domain-name "$PRIMARY" \
    $SAN_ARGS \
    --validation-method "$VALIDATION" \
    --idempotency-token "$(echo "$PRIMARY" | md5sum | cut -c1-16)" \
    $TAG_ARGS \
    --region "$REGION" \
    --query 'CertificateArn' \
    --output text)

log "Certificate ARN: $CERT_ARN"

section "2 — Validation Instructions"

if [[ "$VALIDATION" == "DNS" ]]; then
    warn "You must add DNS CNAME records to validate domain ownership."
    warn "Waiting 15 seconds for ACM to generate validation records..."
    sleep 15

    log "Retrieving DNS validation records..."
    VALIDATION_INFO=$(aws acm describe-certificate \
        --certificate-arn "$CERT_ARN" \
        --region "$REGION" \
        --query 'Certificate.DomainValidationOptions[*].{Domain:DomainName,Name:ResourceRecord.Name,Value:ResourceRecord.Value}' \
        --output table)

    echo ""
    echo "$VALIDATION_INFO"
    echo ""
    warn "Add these CNAME records to your DNS zone, then wait up to 30 minutes for validation."
    warn "Once validated, ACM renews the certificate automatically — no further action needed."
else
    warn "ACM has sent validation emails to the domain owner contacts."
    warn "Click the approval link in the email to validate the certificate."
fi

section "3 — Wait for Validation (optional)"
echo ""
read -rp "Wait for certificate to become valid? (may take 5-30 min) [y/N] " wait_for_cert
if [[ "${wait_for_cert,,}" == "y" ]]; then
    log "Waiting for certificate validation..."
    aws acm wait certificate-validated \
        --certificate-arn "$CERT_ARN" \
        --region "$REGION"
    log "Certificate is now VALID"
fi

section "Next Steps"
echo ""
echo "  Certificate ARN (save this):"
echo "  $CERT_ARN"
echo ""
echo "  Attach to an ALB:"
echo "  aws elbv2 add-listener-certificates --listener-arn <ALB_LISTENER_ARN> \\"
echo "    --certificates CertificateArn=$CERT_ARN"
echo ""
echo "  Attach to CloudFront:"
echo "  Specify the ARN in your CloudFront distribution's ViewerCertificate config."
echo "  (CloudFront requires certificates in us-east-1 region)"
echo ""
echo "  View all ACM certificates:"
echo "  aws acm list-certificates --region $REGION"
