#!/usr/bin/env bash
# =============================================================================
# provision-semaphore.sh
# =============================================================================
# Installs Semaphore UI — a lightweight web front-end for running Ansible
# playbooks. Called by Packer after provision-ansible-server.sh has already
# installed Ansible and set up the ansible service account.
#
# What this script installs:
#   • Semaphore (latest release, installed via .deb)
#   • nginx (reverse proxy — access Semaphore on port 80, not 3000)
#   • BoltDB (embedded database — no MySQL/PostgreSQL required)
#   • systemd service for Semaphore (enabled at boot)
#
# Environment variables (injected by Packer template):
#   SEMAPHORE_ADMIN_PASS — initial admin password (CHANGE after first login)
#
# After first boot:
#   1. Open http://<server-ip>/ in a browser
#   2. Log in: admin / <SEMAPHORE_ADMIN_PASS>
#   3. Add a new Project → point it at your GitHub repo
#   4. Add an SSH Key (the ansible user's private key)
#   5. Create an Inventory pointing at /opt/ansible/inventory/hosts.yml
#   6. Run playbooks from the web UI
#
# Author  : IT-Architect-UK
# Repo    : https://github.com/IT-Architect-UK/monorepo
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
log()     { echo -e "${GREEN}[✔]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
fail()    { echo -e "${RED}[✘]${NC} $*" >&2; exit 1; }
section() { echo -e "\n${BLUE}${BOLD}━━━ $* ━━━${NC}"; }

# ── Configuration ─────────────────────────────────────────────────────────────
SEMAPHORE_USER="semaphore"
SEMAPHORE_DATA_DIR="/var/lib/semaphore"
SEMAPHORE_CONFIG_DIR="/etc/semaphore"
SEMAPHORE_CONFIG="${SEMAPHORE_CONFIG_DIR}/config.json"
SEMAPHORE_LOG_DIR="/var/log/semaphore"
SEMAPHORE_ADMIN_PASS="${SEMAPHORE_ADMIN_PASS:-}"
SEMAPHORE_PORT="3000"

section "Semaphore UI Provisioner"

# ── Pre-flight ─────────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || fail "Must run as root"

if [[ -z "${SEMAPHORE_ADMIN_PASS}" ]]; then
    # Generate a random password if none provided — printed to build log
    SEMAPHORE_ADMIN_PASS="$(openssl rand -base64 12 | tr -d '=+/')"
    warn "SEMAPHORE_ADMIN_PASS not set — generated password: ${SEMAPHORE_ADMIN_PASS}"
    warn "Record this now — it will not be shown again"
fi

# ── 1. Detect latest Semaphore release ───────────────────────────────────────
section "1 — Detect Semaphore version"
SEMAPHORE_VERSION=$(curl -sf --max-time 15 \
    "https://api.github.com/repos/semaphoreui/semaphore/releases/latest" \
    | grep '"tag_name"' \
    | sed 's/.*"v\([^"]*\)".*/\1/')

[[ -n "${SEMAPHORE_VERSION}" ]] || fail "Could not detect latest Semaphore version from GitHub API"
log "Semaphore version: ${SEMAPHORE_VERSION}"

# ── 2. Download and install Semaphore deb ────────────────────────────────────
section "2 — Install Semaphore"
DEB_URL="https://github.com/semaphoreui/semaphore/releases/download/v${SEMAPHORE_VERSION}/semaphore_community_${SEMAPHORE_VERSION}_linux_amd64.deb"
log "Downloading from: ${DEB_URL}"
# -f: treat HTTP errors as failures instead of silently saving an error page
# as if it were the .deb. --retry: survive transient network blips. 300s
# timeout: a 60s cap was too tight for this asset size over some links and
# was truncating the download (dpkg then failed with a cryptic archive error).
curl -fsSL --retry 3 --retry-delay 5 --max-time 300 "${DEB_URL}" -o /tmp/semaphore.deb \
    || fail "Failed to download Semaphore deb from ${DEB_URL}"

[[ -s /tmp/semaphore.deb ]] \
    || fail "Downloaded semaphore.deb is empty (0 bytes) — check network connectivity to github.com"

dpkg -i /tmp/semaphore.deb || fail "Failed to install Semaphore deb"
rm -f /tmp/semaphore.deb
log "Semaphore $(semaphore version 2>/dev/null || echo ${SEMAPHORE_VERSION}) installed"

# ── 3. Create semaphore OS user ───────────────────────────────────────────────
section "3 — Create semaphore user"
if ! id "${SEMAPHORE_USER}" &>/dev/null; then
    useradd \
        --system \
        --shell /bin/bash \
        --home-dir "${SEMAPHORE_DATA_DIR}" \
        --no-create-home \
        --comment "Semaphore UI service account" \
        "${SEMAPHORE_USER}"
    log "User '${SEMAPHORE_USER}' created"
else
    log "User '${SEMAPHORE_USER}' already exists"
fi

# Add semaphore user to the ansible group so it can read /opt/ansible/
if getent group ansible &>/dev/null; then
    usermod -aG ansible "${SEMAPHORE_USER}"
    log "Added '${SEMAPHORE_USER}' to 'ansible' group"
fi

# ── 4. Create directories ─────────────────────────────────────────────────────
section "4 — Directories"
mkdir -p \
    "${SEMAPHORE_DATA_DIR}" \
    "${SEMAPHORE_DATA_DIR}/tmp" \
    "${SEMAPHORE_CONFIG_DIR}" \
    "${SEMAPHORE_LOG_DIR}"

chown -R "${SEMAPHORE_USER}:${SEMAPHORE_USER}" \
    "${SEMAPHORE_DATA_DIR}" \
    "${SEMAPHORE_CONFIG_DIR}" \
    "${SEMAPHORE_LOG_DIR}"
chmod 750 "${SEMAPHORE_CONFIG_DIR}"
log "Directories created"

# ── 5. Generate config ────────────────────────────────────────────────────────
section "5 — Write config"
COOKIE_HASH=$(openssl rand -hex 32)
COOKIE_ENC=$(openssl rand -hex 16)
ACCESS_KEY_ENC=$(openssl rand -base64 32 | tr -d '\n=')

cat > "${SEMAPHORE_CONFIG}" << EOF
{
  "bolt": {
    "host": "${SEMAPHORE_DATA_DIR}/semaphore.db"
  },
  "dialect":    "bolt",
  "port":       ":${SEMAPHORE_PORT}",
  "interface":  "127.0.0.1",
  "tmp_path":   "${SEMAPHORE_DATA_DIR}/tmp",

  "cookie_hash":          "${COOKIE_HASH}",
  "cookie_encryption":    "${COOKIE_ENC}",
  "access_key_encryption": "${ACCESS_KEY_ENC}",

  "email_alert":    false,
  "slack_alert":    false,
  "telegram_alert": false,

  "use_remote_runner": false
}
EOF

chown "${SEMAPHORE_USER}:${SEMAPHORE_USER}" "${SEMAPHORE_CONFIG}"
chmod 600 "${SEMAPHORE_CONFIG}"
log "Config written to ${SEMAPHORE_CONFIG}"

# ── 6. Initialise database and create admin user ─────────────────────────────
section "6 — Initialise database"

# Migrate creates the BoltDB schema without starting the HTTP server
sudo -u "${SEMAPHORE_USER}" semaphore migrate --config "${SEMAPHORE_CONFIG}" \
    || fail "semaphore migrate failed"
log "Database initialised"

sudo -u "${SEMAPHORE_USER}" semaphore user add \
    --admin \
    --login  "admin" \
    --name   "Admin" \
    --email  "admin@localhost" \
    --password "${SEMAPHORE_ADMIN_PASS}" \
    --config "${SEMAPHORE_CONFIG}" \
    || fail "semaphore user add failed"
log "Admin user 'admin' created"

# ── 7. systemd service ────────────────────────────────────────────────────────
section "7 — systemd service"
cat > /etc/systemd/system/semaphore.service << EOF
[Unit]
Description=Semaphore Ansible UI
Documentation=https://semaphoreui.com
After=network.target

[Service]
Type=simple
User=${SEMAPHORE_USER}
Group=${SEMAPHORE_USER}
WorkingDirectory=${SEMAPHORE_DATA_DIR}
ExecStart=/usr/bin/semaphore server --config ${SEMAPHORE_CONFIG}
Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=semaphore

# Harden the service
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${SEMAPHORE_DATA_DIR} ${SEMAPHORE_LOG_DIR}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable semaphore
log "semaphore.service enabled (starts on boot)"

# ── 8. Install nginx ──────────────────────────────────────────────────────────
section "8 — nginx reverse proxy"
export DEBIAN_FRONTEND=noninteractive
apt-get install -y nginx
log "nginx installed"

# Remove default site
rm -f /etc/nginx/sites-enabled/default

# Write Semaphore site config
cat > /etc/nginx/sites-available/semaphore << 'NGINX_EOF'
# Semaphore UI — nginx reverse proxy
# Proxies port 80 → Semaphore on 127.0.0.1:3000
#
# To add HTTPS later:
#   1. Install certbot: apt-get install -y certbot python3-certbot-nginx
#   2. Run: certbot --nginx -d your.domain.com
#   OR use the configure-tls.yml Ansible playbook in this repo

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    # Allow large file uploads (SSH keys, inventory files)
    client_max_body_size 16M;

    # Security headers
    add_header X-Frame-Options       "SAMEORIGIN"  always;
    add_header X-Content-Type-Options "nosniff"    always;
    add_header X-XSS-Protection      "1; mode=block" always;

    location / {
        proxy_pass         http://127.0.0.1:3000;
        proxy_http_version 1.1;

        # WebSocket support (Semaphore uses WS for live task output)
        proxy_set_header Upgrade    $http_upgrade;
        proxy_set_header Connection "upgrade";

        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_read_timeout    120s;
        proxy_connect_timeout 120s;
        proxy_send_timeout    120s;

        proxy_cache_bypass $http_upgrade;
    }
}
NGINX_EOF

ln -sf /etc/nginx/sites-available/semaphore /etc/nginx/sites-enabled/semaphore
nginx -t || fail "nginx config test failed"
systemctl enable nginx
log "nginx configured and enabled (port 80 → Semaphore :3000)"

# ── Summary ───────────────────────────────────────────────────────────────────
section "Semaphore Provisioning Complete"
log "Version        : ${SEMAPHORE_VERSION}"
log "Config         : ${SEMAPHORE_CONFIG}"
log "Data directory : ${SEMAPHORE_DATA_DIR}"
log "Service        : semaphore.service (enabled at boot)"
log "Access         : http://<server-ip>/ (via nginx on port 80)"
log "Admin login    : admin / <SEMAPHORE_ADMIN_PASS set at build time>"
echo ""
log "Post-boot setup:"
log "  1. Open http://<server-ip>/ and log in"
log "  2. Add Project → git repo URL (https://github.com/IT-Architect-UK/monorepo)"
log "  3. Add SSH Key → paste /home/ansible/.ssh/id_ed25519 private key"
log "  4. Add Inventory → /opt/ansible/inventory/hosts.yml"
log "  5. Create Tasks → select playbook, inventory, SSH key and run"
