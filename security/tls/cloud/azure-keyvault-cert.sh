#!/usr/bin/env bash
# =============================================================================
# azure-keyvault-cert.sh
# =============================================================================
# Creates or imports a TLS certificate in Azure Key Vault.
#
# What is Azure Key Vault?
# ────────────────────────
# Azure Key Vault is a cloud secret and certificate store. It can:
#   1. Generate self-signed certificates (for internal/dev use)
#   2. Order certificates from a CA (DigiCert or GlobalSign) automatically
#   3. Store and manage certificates you import from other sources
#
# Certificates stored in Key Vault can be:
#   - Mounted to Azure App Service (zero-config HTTPS)
#   - Used by Azure Application Gateway (WAF + HTTPS termination)
#   - Accessed by VMs and AKS via the Key Vault CSI driver
#
# Prerequisites:
#   - Azure CLI: https://docs.microsoft.com/cli/azure/install-azure-cli
#   - Logged in: az login
#   - Existing Key Vault (or use --create-vault flag)
#
# Usage:
#   # Create a self-signed certificate (dev/lab)
#   ./azure-keyvault-cert.sh -v mykeyvault -n example-com -d "CN=example.com"
#
#   # Import a PEM certificate from Let's Encrypt
#   ./azure-keyvault-cert.sh -v mykeyvault -n example-com --import --cert fullchain.pem --key privkey.pem
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

VAULT=""; CERT_NAME=""; SUBJECT=""; IMPORT=false; CERT_FILE=""; KEY_FILE=""
VALIDITY_MONTHS=12

while getopts "v:n:d:m:ih" opt; do
    case $opt in
        v) VAULT="$OPTARG" ;;
        n) CERT_NAME="$OPTARG" ;;
        d) SUBJECT="$OPTARG" ;;
        m) VALIDITY_MONTHS="$OPTARG" ;;
        i) IMPORT=true ;;
        h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) error "Unknown option" ;;
    esac
done

# Remaining args for --import: --cert and --key
for arg in "$@"; do
    [[ "$arg" == "--import" ]] && IMPORT=true
    [[ "$arg" =~ ^--cert=(.+)$ ]] && CERT_FILE="${BASH_REMATCH[1]}"
    [[ "$arg" =~ ^--key=(.+)$ ]]  && KEY_FILE="${BASH_REMATCH[1]}"
done

[[ -z "$VAULT" ]]      && error "Specify Key Vault name with -v"
[[ -z "$CERT_NAME" ]]  && error "Specify certificate name with -n"
command -v az &>/dev/null || error "Azure CLI not installed"
az account show &>/dev/null || error "Not logged in to Azure. Run: az login"

section "Azure Key Vault — Certificate Management"

if [[ "$IMPORT" == "true" ]]; then
    section "Import Certificate into Key Vault"
    [[ -z "$CERT_FILE" ]] && error "Specify --cert=<path>"
    [[ -z "$KEY_FILE" ]]  && error "Specify --key=<path>"

    log "Converting PEM to PFX for Azure import..."
    TEMP_PFX=$(mktemp --suffix=.pfx)
    PFX_PASS="TempPass$(date +%s)"
    openssl pkcs12 -export -in "$CERT_FILE" -inkey "$KEY_FILE" -out "$TEMP_PFX" -passout "pass:$PFX_PASS"

    log "Importing into Key Vault '$VAULT'..."
    az keyvault certificate import \
        --vault-name "$VAULT" \
        --name "$CERT_NAME" \
        --file "$TEMP_PFX" \
        --password "$PFX_PASS"

    rm -f "$TEMP_PFX"
    log "Certificate '$CERT_NAME' imported to Key Vault '$VAULT'"
else
    section "Create Self-Signed Certificate"
    [[ -z "$SUBJECT" ]] && SUBJECT="CN=${CERT_NAME}"
    log "Creating self-signed certificate: $SUBJECT"

    # Policy defines the certificate properties
    POLICY=$(az keyvault certificate get-default-policy)
    POLICY_FILE=$(mktemp --suffix=.json)
    echo "$POLICY" | jq --arg subject "$SUBJECT" --argjson months "$VALIDITY_MONTHS" \
        '.x509CertificateProperties.subject = $subject |
         .attributes.validityInMonths = $months' > "$POLICY_FILE"

    az keyvault certificate create \
        --vault-name "$VAULT" \
        --name "$CERT_NAME" \
        --policy @"$POLICY_FILE"

    rm -f "$POLICY_FILE"
    log "Certificate '$CERT_NAME' created in Key Vault '$VAULT'"
fi

section "Certificate Details"
az keyvault certificate show \
    --vault-name "$VAULT" \
    --name "$CERT_NAME" \
    --query '{Name:name, Enabled:attributes.enabled, Expires:attributes.expires, Thumbprint:x509Thumbprint}' \
    --output table

section "Next Steps"
echo ""
echo "  Use with Azure App Service:"
echo "  az webapp config ssl import --resource-group <RG> --name <APP> \\"
echo "    --key-vault $VAULT --key-vault-certificate-name $CERT_NAME"
echo ""
echo "  Download certificate (PFX):"
echo "  az keyvault secret download --vault-name $VAULT --name $CERT_NAME --file cert.pfx --encoding base64"
