#!/usr/bin/env bash
# =============================================================================
# install-uptime-kuma-docker.sh
# =============================================================================
# Installs Uptime Kuma using Docker — a self-hosted monitoring dashboard that
# checks whether your websites and services are up or down.
#
# What is Uptime Kuma?
# ────────────────────
# Uptime Kuma is a beautiful, self-hosted alternative to services like
# UptimeRobot. It monitors URLs, TCP ports, DNS records, Docker containers,
# and more. It sends alerts via email, Slack, Discord, Telegram, and 50+ others.
#
# Features:
#   - HTTP/HTTPS URL monitoring
#   - TCP port checks
#   - Ping monitoring
#   - DNS record checks
#   - Docker container monitoring
#   - Public status pages
#   - 90+ notification providers
#   - Response time graphs
#   - Incident history
#
# Prerequisites:
#   - Docker installed (run deploy-docker.yml Ansible playbook or deploy-docker.sh)
#   - Port 3001 available
#
# Usage:
#   ./install-uptime-kuma-docker.sh
#   ./install-uptime-kuma-docker.sh --port 3001 --data-dir /opt/uptime-kuma
#
# Options:
#   --port PORT        Port to expose Uptime Kuma on (default: 3001)
#   --data-dir DIR     Data directory for persistent storage (default: /opt/uptime-kuma/data)
#   --with-nginx       Set up Nginx reverse proxy for HTTPS access
#   --domain DOMAIN    Domain name (required if --with-nginx is set)
#   --email EMAIL      Email for Let's Encrypt (required if --with-nginx)
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

PORT=3001; DATA_DIR="/opt/uptime-kuma/data"; WITH_NGINX=false; DOMAIN=""; EMAIL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --port)       PORT="$2";     shift 2 ;;
        --data-dir)   DATA_DIR="$2"; shift 2 ;;
        --with-nginx) WITH_NGINX=true; shift ;;
        --domain)     DOMAIN="$2";   shift 2 ;;
        --email)      EMAIL="$2";    shift 2 ;;
        *) error "Unknown option: $1" ;;
    esac
done

[[ $WITH_NGINX == true && -z "$DOMAIN" ]] && error "Specify --domain when using --with-nginx"
[[ $WITH_NGINX == true && -z "$EMAIL" ]]  && error "Specify --email when using --with-nginx"
command -v docker &>/dev/null || error "Docker not installed. Run the deploy-docker playbook first."

section "Uptime Kuma — Installation"
log "Port     : $PORT"
log "Data dir : $DATA_DIR"

section "1 — Create Data Directory"
mkdir -p "$DATA_DIR"
log "Data directory: $DATA_DIR"

section "2 — Deploy Uptime Kuma Container"

# Stop and remove existing container if it exists
if docker ps -a --format '{{.Names}}' | grep -q "^uptime-kuma$"; then
    warn "Existing 'uptime-kuma' container found — removing..."
    docker stop uptime-kuma 2>/dev/null || true
    docker rm uptime-kuma 2>/dev/null || true
fi

docker run -d \
    --name uptime-kuma \
    --restart unless-stopped \
    -p "${PORT}:3001" \
    -v "${DATA_DIR}:/app/data" \
    -v /var/run/docker.sock:/var/run/docker.sock:ro \
    louislam/uptime-kuma:latest

log "Container started"

# Wait for startup
log "Waiting for Uptime Kuma to start..."
for i in $(seq 1 30); do
    if curl -sf "http://localhost:${PORT}" &>/dev/null; then
        log "Uptime Kuma is responding"
        break
    fi
    [[ $i -eq 30 ]] && error "Uptime Kuma did not start within 60 seconds"
    sleep 2
done

section "3 — Firewall Rule"
if command -v ufw &>/dev/null; then
    ufw allow "$PORT/tcp" comment "Uptime Kuma" 2>/dev/null || true
    log "UFW rule added for port $PORT"
fi

if [[ "$WITH_NGINX" == "true" ]]; then
    section "4 — Nginx Reverse Proxy + TLS"
    apt-get install -y nginx certbot python3-certbot-nginx -q

    cat > "/etc/nginx/sites-available/uptime-kuma.conf" << NGINXEOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        # WebSocket support (Uptime Kuma uses WebSockets for real-time updates)
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
NGINXEOF

    ln -sf /etc/nginx/sites-available/uptime-kuma.conf /etc/nginx/sites-enabled/
    nginx -t && systemctl reload nginx

    certbot --nginx --non-interactive --agree-tos --email "$EMAIL" -d "$DOMAIN"
    log "HTTPS configured for $DOMAIN"
fi

section "Complete!"
echo ""
log "Uptime Kuma is running!"
echo ""
if [[ "$WITH_NGINX" == "true" ]]; then
    echo "  Access at : https://$DOMAIN"
else
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo "  Access at : http://$SERVER_IP:$PORT"
fi
echo ""
echo "  First time setup:"
echo "  1. Open the URL above in your browser"
echo "  2. Create an admin username and password"
echo "  3. Click '+ Add New Monitor' to add your first check"
echo ""
echo "  Common monitor types to add:"
echo "  - HTTP(s)  → your websites and APIs"
echo "  - TCP Port → SSH (22), RDP (3389), database ports"
echo "  - Ping     → servers and network devices"
echo "  - Docker   → running containers on this host"
echo ""
echo "  Docker management:"
echo "  docker logs uptime-kuma      ← view logs"
echo "  docker restart uptime-kuma   ← restart"
echo "  docker stop uptime-kuma      ← stop"
