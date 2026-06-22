#!/usr/bin/env bash
# =============================================================================
# backup-to-s3.sh
# =============================================================================
# Configures Restic to back up to AWS S3 (or any S3-compatible storage like
# Backblaze B2, MinIO, Wasabi, or Cloudflare R2).
#
# Why S3 for backups?
# ────────────────────
# Storing backups off-site protects against local disasters (fire, theft,
# hardware failure). S3 is reliable (99.999999999% durability), cheap
# (~$0.023/GB/month for Standard), and accessible from anywhere.
#
# Usage:
#   sudo ./backup-to-s3.sh \
#     --bucket my-backup-bucket \
#     --region eu-west-2 \
#     --access-key AKIAEXAMPLE \
#     --secret-key mysecretkey \
#     --password myencryptionpassword
#
# For Backblaze B2 (cheaper than S3):
#   sudo ./backup-to-s3.sh \
#     --bucket my-b2-bucket \
#     --endpoint s3.us-west-002.backblazeb2.com \
#     --access-key B2_APP_KEY_ID \
#     --secret-key B2_APP_KEY \
#     --password myencryptionpassword
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

BUCKET=""; REGION="us-east-1"; ENDPOINT=""; ACCESS_KEY=""; SECRET_KEY=""; PASSWORD=""
PATHS="/etc /home"; SCHEDULE="02:30"
KEEP_DAILY=7; KEEP_WEEKLY=4; KEEP_MONTHLY=3

while [[ $# -gt 0 ]]; do
    case $1 in
        --bucket)       BUCKET="$2";     shift 2 ;;
        --region)       REGION="$2";     shift 2 ;;
        --endpoint)     ENDPOINT="$2";   shift 2 ;;
        --access-key)   ACCESS_KEY="$2"; shift 2 ;;
        --secret-key)   SECRET_KEY="$2"; shift 2 ;;
        --password)     PASSWORD="$2";   shift 2 ;;
        --paths)        PATHS="$2";      shift 2 ;;
        --schedule)     SCHEDULE="$2";   shift 2 ;;
        *) error "Unknown option: $1" ;;
    esac
done

[[ $EUID -ne 0 ]]     && error "Run as root: sudo $0"
[[ -z "$BUCKET" ]]    && error "Specify --bucket"
[[ -z "$ACCESS_KEY" ]] && error "Specify --access-key"
[[ -z "$SECRET_KEY" ]] && error "Specify --secret-key"
[[ -z "$PASSWORD" ]]  && error "Specify --password (encryption key)"
command -v restic &>/dev/null || error "Restic not installed. Run install-restic.sh first."

# Build repository URL
if [[ -n "$ENDPOINT" ]]; then
    REPO="s3:${ENDPOINT}/${BUCKET}/$(hostname)"
else
    REPO="s3:s3.amazonaws.com/${BUCKET}/$(hostname)"
fi

section "Restic — S3 Backup Setup"
log "Repository : $REPO"
log "Region     : $REGION"
log "Paths      : $PATHS"

section "1 — Create Configuration"
mkdir -p /etc/restic; chmod 700 /etc/restic

echo "$PASSWORD" > /etc/restic/password; chmod 600 /etc/restic/password

cat > /etc/restic/environment << ENV
RESTIC_REPOSITORY=$REPO
RESTIC_PASSWORD_FILE=/etc/restic/password
AWS_ACCESS_KEY_ID=$ACCESS_KEY
AWS_SECRET_ACCESS_KEY=$SECRET_KEY
AWS_DEFAULT_REGION=$REGION
ENV
chmod 600 /etc/restic/environment
log "Configuration saved to /etc/restic/environment"

section "2 — Initialise Repository"
set -a; source /etc/restic/environment; set +a
restic init && log "Repository initialised" || {
    restic snapshots &>/dev/null && log "Repository already exists" || error "Failed to initialise repository"
}

section "3 — Create Backup Script"
cat > /usr/local/bin/restic-backup << SCRIPT
#!/usr/bin/env bash
set -euo pipefail
set -a; source /etc/restic/environment; set +a
echo "[\$(date)] Backup to S3: \$RESTIC_REPOSITORY"
restic backup --verbose --one-file-system $PATHS
restic forget --prune --keep-daily $KEEP_DAILY --keep-weekly $KEEP_WEEKLY --keep-monthly $KEEP_MONTHLY
restic check
echo "[\$(date)] Backup complete"
SCRIPT
chmod +x /usr/local/bin/restic-backup

section "4 — systemd Timer"
cat > /etc/systemd/system/restic-backup.service << SVC
[Unit]
Description=Restic S3 Backup
After=network.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/restic-backup
StandardOutput=journal
StandardError=journal
SVC
cat > /etc/systemd/system/restic-backup.timer << TMR
[Unit]
Description=Daily S3 Backup at $SCHEDULE
[Timer]
OnCalendar=*-*-* $SCHEDULE:00
Persistent=true
[Install]
WantedBy=timers.target
TMR
systemctl daemon-reload
systemctl enable --now restic-backup.timer
log "Timer active — backups run daily at $SCHEDULE"

section "5 — First Backup"
/usr/local/bin/restic-backup

section "Complete!"
echo ""
log "Encrypted backups are now stored in S3: $REPO"
echo ""
echo "  Verify: restic -r $REPO snapshots"
warn "Store your password safely. Without it, backups cannot be restored."
