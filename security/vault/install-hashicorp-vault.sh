#!/usr/bin/env bash
# =============================================================================
# HashiCorp Vault Installation — Ubuntu
# Installs the latest Vault release from the HashiCorp apt repository,
# generates a self-signed TLS certificate, configures Vault with Raft
# integrated storage, creates a systemd service, and performs the initial
# operator init and unseal.
#
# WARNING: The generated unseal key and root token are saved to a local file
# during initial setup. Move them to a secure secrets store (e.g. another
# Vault instance, a password manager, or a hardware key) immediately.
#
# Usage:
#   sudo ./install-hashicorp-vault.sh
#   sudo ./install-hashicorp-vault.sh --fqdn vault.corp.local --install-dir /opt/vault
#
# Options:
#   --fqdn <hostname>      Vault server FQDN (default: auto-detected)
#   --install-dir <path>   Vault installation directory (default: /opt/vault)
#
# Author:            Darren Pilkington
# Version:           1.1
# Date:              31-05-2026
# =============================================================================

set -euo pipefail

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/var/log/vault-install"
LOG_FILE="${LOG_DIR}/install-vault-$(date '+%Y%m%d-%H%M%S').log"
mkdir -p "${LOG_DIR}"

log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

# ─── Argument parsing ────────────────────────────────────────────────────────
FQDN=""
INSTALL_DIR="/opt/vault"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fqdn)        FQDN="$2";        shift 2 ;;
        --install-dir) INSTALL_DIR="$2"; shift 2 ;;
        --help)
            grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,2\}//'
            exit 0
            ;;
        *) fail "Unknown argument: $1. Use --help for usage." ;;
    esac
done

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || fail "Run as root: sudo ./install-hashicorp-vault.sh"
command -v apt-get &>/dev/null || fail "apt-get not found — Ubuntu/Debian required."

# Resolve FQDN and IP
[[ -z "${FQDN}" ]] && FQDN=$(hostname --fqdn 2>/dev/null || hostname)
IP_ADDRESS=$(hostname -I | awk '{print $1}')

log "Installing HashiCorp Vault on $(hostname -f 2>/dev/null || hostname)"
log "  FQDN         : ${FQDN}"
log "  IP address   : ${IP_ADDRESS}"
log "  Install dir  : ${INSTALL_DIR}"
log "Log file: ${LOG_FILE}"

# ─── Install prerequisites ───────────────────────────────────────────────────
log "Installing prerequisites..."
apt-get update -y 2>&1 | tee -a "${LOG_FILE}"
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release openssl \
    2>&1 | tee -a "${LOG_FILE}"

# ─── Create Vault system user ────────────────────────────────────────────────
VAULT_USER="vault"
VAULT_GROUP="vault"
if ! id "${VAULT_USER}" &>/dev/null; then
    log "Creating Vault system user..."
    groupadd "${VAULT_GROUP}"
    useradd -r -s /usr/sbin/nologin -g "${VAULT_GROUP}" -d "${INSTALL_DIR}" "${VAULT_USER}"
    log "Vault user created."
else
    log "Vault user already exists."
fi

# ─── Add HashiCorp APT repository ────────────────────────────────────────────
log "Adding HashiCorp GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg
chmod a+r /etc/apt/keyrings/hashicorp-archive-keyring.gpg
log "GPG key added."

log "Adding HashiCorp apt repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] \
https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    | tee /etc/apt/sources.list.d/hashicorp.list > /dev/null
log "Repository added."

# ─── Install Vault ────────────────────────────────────────────────────────────
log "Installing Vault..."
apt-get update -y 2>&1 | tee -a "${LOG_FILE}"
apt-get install -y vault 2>&1 | tee -a "${LOG_FILE}"

VAULT_VERSION=$(vault version | awk '{print $2}')
log "Vault ${VAULT_VERSION} installed."

# ─── Prepare installation directory ─────────────────────────────────────────
log "Preparing installation directory: ${INSTALL_DIR}..."
mkdir -p "${INSTALL_DIR}"/{vault-data,tls}
chown -R "${VAULT_USER}:${VAULT_GROUP}" "${INSTALL_DIR}"
chmod 750 "${INSTALL_DIR}"

# ─── Generate self-signed TLS certificate ────────────────────────────────────
CERT_FILE="${INSTALL_DIR}/tls/vault.crt"
KEY_FILE="${INSTALL_DIR}/tls/vault.key"

log "Generating self-signed TLS certificate for ${FQDN}..."
openssl req -x509 -newkey rsa:4096 -sha256 -days 365 \
    -noenc \
    -keyout "${KEY_FILE}" \
    -out    "${CERT_FILE}" \
    -subj   "/CN=${FQDN}" \
    -addext "subjectAltName=DNS:${FQDN},IP:${IP_ADDRESS}" \
    2>&1 | tee -a "${LOG_FILE}"

chown "${VAULT_USER}:${VAULT_GROUP}" "${CERT_FILE}" "${KEY_FILE}"
chmod 640 "${KEY_FILE}"
chmod 644 "${CERT_FILE}"
log "TLS certificate generated."

# ─── Write Vault configuration ───────────────────────────────────────────────
VAULT_CONFIG="${INSTALL_DIR}/vault.hcl"
log "Writing Vault configuration to ${VAULT_CONFIG}..."

cat > "${VAULT_CONFIG}" <<EOF
# HashiCorp Vault Configuration
# Generated by install-hashicorp-vault.sh on $(date '+%Y-%m-%d %H:%M:%S')

api_addr     = "https://${FQDN}:8200"
cluster_addr = "https://${FQDN}:8201"
ui           = true
disable_mlock = true

listener "tcp" {
  address       = "0.0.0.0:8200"
  tls_cert_file = "${CERT_FILE}"
  tls_key_file  = "${KEY_FILE}"
}

storage "raft" {
  path    = "${INSTALL_DIR}/vault-data"
  node_id = "$(hostname -s)"
}
EOF

chown "${VAULT_USER}:${VAULT_GROUP}" "${VAULT_CONFIG}"
chmod 640 "${VAULT_CONFIG}"
log "Vault configuration written."

# ─── Systemd service ─────────────────────────────────────────────────────────
log "Creating Vault systemd service..."
cat > /etc/systemd/system/vault.service <<EOF
[Unit]
Description=HashiCorp Vault
Documentation=https://www.vaultproject.io/docs
Wants=network-online.target
After=network-online.target

[Service]
User=${VAULT_USER}
Group=${VAULT_GROUP}
ExecStart=/usr/bin/vault server -config=${VAULT_CONFIG}
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
LimitNOFILE=65536
LimitMEMLOCK=infinity
AmbientCapabilities=CAP_IPC_LOCK
NoNewPrivileges=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable vault.service
log "Systemd service created and enabled."

# ─── Start Vault ─────────────────────────────────────────────────────────────
log "Starting Vault service..."
systemctl start vault.service
sleep 5
systemctl is-active vault.service || fail "Vault service failed to start. Check: journalctl -u vault.service"
log "Vault service is running."

# ─── Initialise Vault ────────────────────────────────────────────────────────
export VAULT_ADDR="https://${FQDN}:8200"
export VAULT_SKIP_VERIFY=true

log "Initialising Vault (1 key share, threshold 1)..."
INIT_OUTPUT=$(vault operator init -key-shares=1 -key-threshold=1 2>&1) \
    || fail "Vault init failed: ${INIT_OUTPUT}"

UNSEAL_KEY=$(echo "${INIT_OUTPUT}" | grep "Unseal Key 1:" | awk '{print $NF}')
ROOT_TOKEN=$(echo "${INIT_OUTPUT}" | grep "Initial Root Token:" | awk '{print $NF}')

[[ -n "${UNSEAL_KEY}" ]] || fail "Could not extract unseal key from init output."
[[ -n "${ROOT_TOKEN}" ]] || fail "Could not extract root token from init output."

# ─── Save credentials (temporary — move to secure storage immediately) ───────
KEY_TOKEN_FILE="${INSTALL_DIR}/init-credentials.txt"
cat > "${KEY_TOKEN_FILE}" <<EOF
# HashiCorp Vault Initial Credentials
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# WARNING: Store these securely and delete this file immediately.
#
Unseal Key: ${UNSEAL_KEY}
Root Token: ${ROOT_TOKEN}
EOF
chown root:root "${KEY_TOKEN_FILE}"
chmod 600 "${KEY_TOKEN_FILE}"
log "Credentials saved to ${KEY_TOKEN_FILE} — delete this file after securing the keys."

# ─── Unseal Vault ─────────────────────────────────────────────────────────────
log "Unsealing Vault..."
vault operator unseal "${UNSEAL_KEY}" 2>&1 | tee -a "${LOG_FILE}"
log "Vault unsealed."

# ─── Summary ─────────────────────────────────────────────────────────────────
log "Vault installation complete."
log "  Vault UI    : https://${FQDN}:8200/ui"
log "  Root Token  : ${ROOT_TOKEN}"
log "  Unseal Key  : ${UNSEAL_KEY}"
log "  Credentials : ${KEY_TOKEN_FILE}"
log "  Log file    : ${LOG_FILE}"
log ""
warn "ACTION REQUIRED: Move ${KEY_TOKEN_FILE} to a secure store and delete it from this server."
warn "To log in: export VAULT_ADDR='https://${FQDN}:8200' && vault login ${ROOT_TOKEN}"
