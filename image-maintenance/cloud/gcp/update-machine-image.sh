#!/usr/bin/env bash
# =============================================================================
# update-machine-image.sh (GCP)
# =============================================================================
# Creates an updated GCP Machine Image from a running instance.
#
# GCP Machine Images capture the complete state of a VM — all disks,
# configuration, and metadata. They are GCP's equivalent of AWS AMIs.
#
# Usage:
#   ./update-machine-image.sh --instance my-template-vm --project my-project
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

INSTANCE=""; PROJECT=""; ZONE="europe-west2-a"
IMAGE_PREFIX="golden-image"

while [[ $# -gt 0 ]]; do
    case $1 in
        --instance)     INSTANCE="$2";      shift 2 ;;
        --project)      PROJECT="$2";       shift 2 ;;
        --zone)         ZONE="$2";          shift 2 ;;
        --image-prefix) IMAGE_PREFIX="$2";  shift 2 ;;
        *) error "Unknown option: $1" ;;
    esac
done

[[ -z "$INSTANCE" ]] && error "Specify --instance"
[[ -z "$PROJECT" ]]  && error "Specify --project"
command -v gcloud &>/dev/null || error "gcloud not installed"

TIMESTAMP=$(date +%Y%m%d-%H%M)
IMAGE_NAME="${IMAGE_PREFIX}-${TIMESTAMP}"

section "GCP Machine Image Update"
log "Instance   : $INSTANCE"
log "Project    : $PROJECT"
log "Image name : $IMAGE_NAME"

section "1 — Apply Updates via gcloud SSH"
log "Running OS updates on $INSTANCE..."
gcloud compute ssh "$INSTANCE" \
    --project="$PROJECT" \
    --zone="$ZONE" \
    --command="sudo apt-get update -q && sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y && sudo apt-get autoremove -y && sudo apt-get clean"
log "Updates applied"

section "2 — Create Machine Image"
log "Creating machine image (the instance stays running)..."
gcloud compute machine-images create "$IMAGE_NAME" \
    --project="$PROJECT" \
    --source-instance="$INSTANCE" \
    --source-instance-zone="$ZONE" \
    --description="Golden image built $(date)" \
    --labels="purpose=golden-image,created=$(date +%Y-%m-%d)"

log "Machine image created: $IMAGE_NAME"

section "Complete!"
echo ""
log "GCP Machine Image ready: $IMAGE_NAME"
echo ""
echo "  Create a VM from this image:"
echo "  gcloud compute instances create new-vm \\"
echo "    --project=$PROJECT --zone=$ZONE \\"
echo "    --source-machine-image=$IMAGE_NAME"
echo ""
echo "  List all machine images:"
echo "  gcloud compute machine-images list --project=$PROJECT"
