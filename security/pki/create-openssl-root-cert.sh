#!/usr/bin/env bash
# =============================================================================
# Generate OpenSSL Root CA — Ubuntu
# Creates a self-signed root Certificate Authority (CA) using OpenSSL.
# Generates a 4096-bit RSA private key and a 10-year self-signed certificate.
# Compatible with OpenSSL 1.x and 3.x (uses -noenc, falls back to -nodes).
#
# Output files (in --output-dir):
#   root-ca.key    — Root CA private key (chmod 400)
#   root-ca.crt    — Root CA certificate (PEM)
#
# Usage:
#   sudo ./create-openssl-root-cert.sh
#   sudo ./create-openssl-root-cert.sh --cn "Acme Corp Root CA" --org "Acme Corp" \
#        --country GB --state England --output-dir /etc/ssl/ca
#
# Options:
#   --cn <name>           Common Name (default: prompted)
#   --org <name>          Organisation name (default: prompted)
#   --country <code>      ISO 3166-1 alpha-2 country code (default: GB)
#   --state <name>        State or province (default: England)
#   --ou <name>           Organisational unit (default: Information Technology)
#   --output-dir <path>   Output directory (default: /opt/ssl/root-ca)
#   --non-interactive     Use defaults without prompting
#
# Author:            Darren Pilkington
# Version:           1.1
# Date:              31-05-2026
# =============================================================================

set -euo pipefail

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/pki"
LOG_FILE="${LOG_DIR}/create-root-ca-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── Argument parsing ────────────────────────────────────────────────────────
COMMON_NAME=""
ORG_NAME=""
COUNTRY="GB"
STATE="England"
ORG_UNIT="Information Technology"
OUTPUT_DIR="/opt/ssl/root-ca"
NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cn)              COMMON_NAME="$2";    shift 2 ;;
        --org)             ORG_NAME="$2";       shift 2 ;;
        --country)         COUNTRY="$2";        shift 2 ;;
        --state)           STATE="$2";          shift 2 ;;
        --ou)              ORG_UNIT="$2";       shift 2 ;;
        --output-dir)      OUTPUT_DIR="$2";     shift 2 ;;
        --non-interactive) NON_INTERACTIVE=true; shift   ;;
        --help)
            grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,2\}//'
            exit 0
            ;;
        *) fail "Unknown argument: $1. Use --help for usage." ;;
    esac
done

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || fail "Run as root: sudo ./create-openssl-root-cert.sh"

# Install OpenSSL if not present
if ! command -v openssl &>/dev/null; then
    log "OpenSSL not found. Installing..."
    apt-get update -y 2>&1 | tee -a "${LOG_FILE}"
    apt-get install -y openssl 2>&1 | tee -a "${LOG_FILE}"
fi

OPENSSL_VERSION=$(openssl version)
log "Using: ${OPENSSL_VERSION}"
log "Log file: ${LOG_FILE}"

# ─── Prompt for missing values (interactive mode) ────────────────────────────
if [[ "${NON_INTERACTIVE}" == false ]]; then
    [[ -z "${COMMON_NAME}" ]] && read -r -p "Common Name [Root CA]: " COMMON_NAME
    [[ -z "${ORG_NAME}" ]]    && read -r -p "Organisation Name: "     ORG_NAME
    read -r -p "Country Code [${COUNTRY}]: "              INPUT; COUNTRY="${INPUT:-${COUNTRY}}"
    read -r -p "State / Province [${STATE}]: "            INPUT; STATE="${INPUT:-${STATE}}"
    read -r -p "Organisational Unit [${ORG_UNIT}]: "      INPUT; ORG_UNIT="${INPUT:-${ORG_UNIT}}"
    read -r -p "Output directory [${OUTPUT_DIR}]: "       INPUT; OUTPUT_DIR="${INPUT:-${OUTPUT_DIR}}"
fi

COMMON_NAME="${COMMON_NAME:-Root CA}"
ORG_NAME="${ORG_NAME:-My Organisation}"

log "Certificate details:"
log "  Common Name : ${COMMON_NAME}"
log "  Organisation: ${ORG_NAME} / ${ORG_UNIT}"
log "  Country     : ${COUNTRY}, ${STATE}"
log "  Output dir  : ${OUTPUT_DIR}"

# ─── Prepare output directory ────────────────────────────────────────────────
log "Preparing output directory: ${OUTPUT_DIR}..."
mkdir -p "${OUTPUT_DIR}"
chmod 700 "${OUTPUT_DIR}"

KEY_FILE="${OUTPUT_DIR}/root-ca.key"
CERT_FILE="${OUTPUT_DIR}/root-ca.crt"

# Warn if files already exist
[[ -f "${KEY_FILE}" ]]  && warn "Existing key file will be overwritten: ${KEY_FILE}"
[[ -f "${CERT_FILE}" ]] && warn "Existing cert file will be overwritten: ${CERT_FILE}"

# ─── Generate private key ────────────────────────────────────────────────────
log "Generating 4096-bit RSA private key..."

# -noenc is the OpenSSL 3.x replacement for -nodes; fall back for older installs
if openssl genrsa --help 2>&1 | grep -q "\-noenc"; then
    openssl genrsa -noenc -out "${KEY_FILE}" 4096 2>&1 | tee -a "${LOG_FILE}"
else
    openssl genrsa -nodes  -out "${KEY_FILE}" 4096 2>&1 | tee -a "${LOG_FILE}"
fi

chmod 400 "${KEY_FILE}"
log "Private key generated: ${KEY_FILE} (chmod 400)"

# ─── Generate self-signed certificate ────────────────────────────────────────
log "Generating self-signed root CA certificate (valid 10 years)..."
SUBJECT="/C=${COUNTRY}/ST=${STATE}/O=${ORG_NAME}/OU=${ORG_UNIT}/CN=${COMMON_NAME}"

openssl req -new -x509 \
    -days 3650 \
    -key "${KEY_FILE}" \
    -out "${CERT_FILE}" \
    -subj "${SUBJECT}" \
    2>&1 | tee -a "${LOG_FILE}"

chmod 444 "${CERT_FILE}"
log "Certificate generated: ${CERT_FILE}"

# ─── Display certificate details ─────────────────────────────────────────────
log "Certificate details:"
openssl x509 -in "${CERT_FILE}" -noout -subject -issuer -dates 2>&1 | tee -a "${LOG_FILE}"

log "Root CA generation complete."
log "  Private key : ${KEY_FILE}"
log "  Certificate : ${CERT_FILE}"
log "  Log file    : ${LOG_FILE}"
log ""
log "IMPORTANT: Secure the private key (${KEY_FILE}) — treat it as highly sensitive."
log "To inspect the certificate: openssl x509 -in ${CERT_FILE} -text -noout"
