#!/usr/bin/env bash
# =============================================================================
# update-managed-image.sh (Azure)
# =============================================================================
# Updates an Azure Managed Image by launching a VM, patching it, and re-capturing.
#
# Azure Managed Images are the Azure equivalent of AMIs or VMware templates.
# They enable deploying identical, pre-configured VMs quickly.
#
# Usage:
#   ./update-managed-image.sh --resource-group myRG --image-name t-ubuntu-2404
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

RG=""; IMAGE_NAME=""; LOCATION="uksouth"; VM_SIZE="Standard_B1s"
ADMIN_USER="imagebuilder"; SSH_KEY_PATH="$HOME/.ssh/id_rsa.pub"

while [[ $# -gt 0 ]]; do
    case $1 in
        --resource-group) RG="$2";         shift 2 ;;
        --image-name)     IMAGE_NAME="$2"; shift 2 ;;
        --location)       LOCATION="$2";   shift 2 ;;
        --vm-size)        VM_SIZE="$2";    shift 2 ;;
        *) error "Unknown option: $1" ;;
    esac
done

[[ -z "$RG" ]]         && error "Specify --resource-group"
[[ -z "$IMAGE_NAME" ]] && error "Specify --image-name"
command -v az &>/dev/null || error "Azure CLI not installed"
az account show &>/dev/null || error "Not logged in. Run: az login"

TEMP_VM="image-builder-$(date +%s)"
TIMESTAMP=$(date +%Y%m%d-%H%M)
NEW_IMAGE_NAME="${IMAGE_NAME}-${TIMESTAMP}"

section "Azure Managed Image Update"
log "Resource group : $RG"
log "Source image   : $IMAGE_NAME"
log "New image name : $NEW_IMAGE_NAME"
log "Location       : $LOCATION"

section "1 — Launch Temporary VM from Existing Image"
log "Creating VM from current image..."
az vm create \
    --resource-group "$RG" \
    --name "$TEMP_VM" \
    --image "$IMAGE_NAME" \
    --admin-username "$ADMIN_USER" \
    --ssh-key-values "$SSH_KEY_PATH" \
    --size "$VM_SIZE" \
    --location "$LOCATION" \
    --output table

VM_IP=$(az vm show -d --resource-group "$RG" --name "$TEMP_VM" --query "publicIps" -o tsv)
log "VM running: $VM_IP"

section "2 — Apply Updates via Run Command"
log "Applying OS updates (this may take 5-10 minutes)..."
az vm run-command invoke \
    --resource-group "$RG" \
    --name "$TEMP_VM" \
    --command-id RunShellScript \
    --scripts "apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y && apt-get autoremove -y && apt-get clean"

log "Sealing image (waagent deprovision)..."
az vm run-command invoke \
    --resource-group "$RG" \
    --name "$TEMP_VM" \
    --command-id RunShellScript \
    --scripts "sudo waagent -deprovision+user -force && echo 'Deprovisioned'"

section "3 — Deallocate and Generalise"
log "Deallocating VM..."
az vm deallocate --resource-group "$RG" --name "$TEMP_VM"
az vm generalize --resource-group "$RG" --name "$TEMP_VM"
log "VM generalised"

section "4 — Capture New Managed Image"
az image create \
    --resource-group "$RG" \
    --name "$NEW_IMAGE_NAME" \
    --source "$TEMP_VM" \
    --hyper-v-generation V2

log "Managed Image created: $NEW_IMAGE_NAME"

section "5 — Cleanup"
log "Deleting temporary VM and resources..."
az vm delete --resource-group "$RG" --name "$TEMP_VM" --yes --no-wait
log "Cleanup initiated (running in background)"

section "Complete!"
echo ""
log "New Managed Image: $NEW_IMAGE_NAME"
echo ""
echo "  Use this image to deploy VMs:"
echo "  az vm create --resource-group $RG --name myVM --image $NEW_IMAGE_NAME \\"
echo "    --admin-username azureuser --ssh-key-values ~/.ssh/id_rsa.pub"
