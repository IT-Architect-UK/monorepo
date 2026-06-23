#!/usr/bin/env bash
# =============================================================================
# gcp-certificate-manager.sh
# =============================================================================
# Creates or imports a TLS certificate using GCP Certificate Manager.
#
# GCP Certificate Manager provides two certificate types:
#   Google-managed  — GCP provisions and auto-renews (like ACM, no Let's Encrypt needed)
#   Self-managed    — You import your own certificate (from Let's Encrypt, etc.)
#
# Usage:
#   # Google-managed certificate (simplest — GCP handles everything)
#   ./gcp-certificate-manager.sh -n my-cert -d example.com -p my-project
#
#   # Import existing certificate
#   ./gcp-certificate-manager.sh -n my-cert -p my-project --import --cert cert.pem --key key.pem
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


CERT_NAME=""; DOMAINS=(); PROJECT=""; IMPORT=false; CERT_FILE=""; KEY_FILE=""

while getopts "n:d:p:ih" opt; do
    case $opt in
        n) CERT_NAME="$OPTARG" ;;
        d) DOMAINS+=("$OPTARG") ;;
        p) PROJECT="$OPTARG" ;;
        i) IMPORT=true ;;
        h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) error "Unknown option" ;;
    esac
done

for arg in "$@"; do
    [[ "$arg" =~ ^--cert=(.+)$ ]] && CERT_FILE="${BASH_REMATCH[1]}"
    [[ "$arg" =~ ^--key=(.+)$ ]]  && KEY_FILE="${BASH_REMATCH[1]}"
done

[[ -z "$CERT_NAME" ]] && error "Specify certificate name with -n"
[[ -z "$PROJECT" ]]   && error "Specify GCP project with -p"
command -v gcloud &>/dev/null || error "gcloud CLI not installed"
gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q . || error "Not logged in. Run: gcloud auth login"

section "GCP Certificate Manager"
PROJECT_FLAG="--project=$PROJECT"

if [[ "$IMPORT" == "true" ]]; then
    section "Import Self-Managed Certificate"
    [[ -z "$CERT_FILE" ]] && error "Specify --cert=<path>"
    [[ -z "$KEY_FILE" ]]  && error "Specify --key=<path>"

    log "Importing certificate '$CERT_NAME'..."
    gcloud certificate-manager certificates create "$CERT_NAME" \
        --certificate-file="$CERT_FILE" \
        --private-key-file="$KEY_FILE" \
        $PROJECT_FLAG

    log "Certificate '$CERT_NAME' imported"
else
    [[ ${#DOMAINS[@]} -eq 0 ]] && error "Specify at least one domain with -d for Google-managed certs"

    section "Create Google-Managed Certificate"
    warn "Google-managed certificates require DNS validation via Certificate Manager map."
    warn "This process takes 15-60 minutes."

    DOMAIN_ARGS=""; for d in "${DOMAINS[@]}"; do DOMAIN_ARGS+="$d,"; done; DOMAIN_ARGS="${DOMAIN_ARGS%,}"

    log "Creating certificate for: $DOMAIN_ARGS"
    gcloud certificate-manager certificates create "$CERT_NAME" \
        --domains="$DOMAIN_ARGS" \
        $PROJECT_FLAG

    log "Certificate request submitted"
    warn "Complete DNS validation to activate it — check Certificate Manager in the console."
fi

section "Certificate Status"
gcloud certificate-manager certificates describe "$CERT_NAME" $PROJECT_FLAG

section "Next Steps"
echo ""
echo "  Attach to a Load Balancer via certificate map:"
echo "  gcloud certificate-manager maps create my-cert-map --project=$PROJECT"
echo "  gcloud certificate-manager maps entries create my-entry \\"
echo "    --map=my-cert-map --certificates=$CERT_NAME --hostname=example.com --project=$PROJECT"
echo ""
echo "  List all certificates:"
echo "  gcloud certificate-manager certificates list --project=$PROJECT"
