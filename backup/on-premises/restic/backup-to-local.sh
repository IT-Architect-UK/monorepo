#!/usr/bin/env bash
# =============================================================================
# backup-to-local.sh
# =============================================================================
# Configures Restic to back up to a local directory (external disk, NAS, NFS mount).
# Sets up a systemd timer for automated daily backups.
#
# Usage:
#   sudo ./backup-to-local.sh --repo /mnt/backup/myserver --password mysecret
#   sudo ./backup-to-local.sh --repo /mnt/nas/backups/$(hostname) --password mysecret --paths "/etc /home /var/www"
#
# Options:
#   --repo REPO          Path to backup repository (required)
#   --password PASS      Encryption password (required — WRITE IT DOWN!)
#   --paths "P1 P2"      Space-separated list of paths to back up (default: /etc /home)
#   --exclude "E1 E2"    Paths to exclude (default: /home/*/.cache /proc /sys)
#   --schedule TIME      Daily backup time in HH:MM format (default: 02:00)
#   --keep-daily N       Daily snapshots to retain (default: 7)
#   --keep-weekly N      Weekly snapshots to retain (default: 4)
#   --keep-monthly N     Monthly snapshots to retain (default: 3)
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

REPO=""; PASSWORD=""
PATHS="/etc /home"
EXCLUDE="/home/*/.cache /proc /sys /dev /run /tmp"
SCHEDULE="02:00"
KEEP_DAILY=7; KEEP_WEEKLY=4; KEEP_MONTHLY=3

while [[ $# -gt 0 ]]; do
    case $1 in
        --repo)          REPO="$2";          shift 2 ;;
        --password)      PASSWORD="$2";      shift 2 ;;
        --paths)         PATHS="$2";         shift 2 ;;
        --exclude)       EXCLUDE="$2";       shift 2 ;;
        --schedule)      SCHEDULE="$2";      shift 2 ;;
        --keep-daily)    KEEP_DAILY="$2";    shift 2 ;;
        --keep-weekly)   KEEP_WEEKLY="$2";   shift 2 ;;
        --keep-monthly)  KEEP_MONTHLY="$2";  shift 2 ;;
        *) error "Unknown option: $1" ;;
    esac
done

[[ $EUID -ne 0 ]]    && error "Run as root: sudo $0"
[[ -z "$REPO" ]]     && error "Specify --repo <path>"
[[ -z "$PASSWORD" ]] && error "Specify --password <pass>"
command -v restic &>/dev/null || error "Restic not installed. Run install-restic.sh first."

section "Restic — Local Backup Setup"
log "Repository : $REPO"
log "Paths      : $PATHS"
log "Schedule   : Daily at $SCHEDULE"
log "Retention  : $KEEP_DAILY daily / $KEEP_WEEKLY weekly / $KEEP_MONTHLY monthly"

section "1 — Create Configuration"
mkdir -p /etc/restic
chmod 700 /etc/restic

echo "$PASSWORD" > /etc/restic/password
chmod 600 /etc/restic/password
log "Password file: /etc/restic/password"

cat > /etc/restic/environment << ENV
RESTIC_REPOSITORY=$REPO
RESTIC_PASSWORD_FILE=/etc/restic/password
ENV
chmod 600 /etc/restic/environment

section "2 — Initialise Repository"
mkdir -p "$REPO"
if restic --password-file /etc/restic/password --repo "$REPO" snapshots &>/dev/null 2>&1; then
    log "Repository already initialised"
else
    restic --password-file /etc/restic/password --repo "$REPO" init
    log "Repository initialised at $REPO"
fi

section "3 — Create Backup Script"
BACKUP_PATHS_ARGS=""; for p in $PATHS; do BACKUP_PATHS_ARGS+="$p "; done
EXCLUDE_ARGS=""; for e in $EXCLUDE; do EXCLUDE_ARGS+="--exclude $e "; done

cat > /usr/local/bin/restic-backup << SCRIPT
#!/usr/bin/env bash
set -euo pipefail

source /etc/restic/environment

echo "[\$(date)] Starting backup to \$RESTIC_REPOSITORY"

# Run backup
restic backup \\
    --verbose \\
    --one-file-system \\
    $EXCLUDE_ARGS \\
    $BACKUP_PATHS_ARGS

# Apply retention policy — remove old snapshots
echo "[\$(date)] Applying retention policy..."
restic forget \\
    --prune \\
    --keep-daily $KEEP_DAILY \\
    --keep-weekly $KEEP_WEEKLY \\
    --keep-monthly $KEEP_MONTHLY

# Verify repository integrity
echo "[\$(date)] Checking repository integrity..."
restic check

echo "[\$(date)] Backup complete"
SCRIPT
chmod +x /usr/local/bin/restic-backup
log "Backup script: /usr/local/bin/restic-backup"

section "4 — Create systemd Timer"
cat > /etc/systemd/system/restic-backup.service << SVCEOF
[Unit]
Description=Restic Backup to $REPO
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/restic-backup
StandardOutput=journal
StandardError=journal
SVCEOF

cat > /etc/systemd/system/restic-backup.timer << TIMEREOF
[Unit]
Description=Daily Restic Backup at $SCHEDULE

[Timer]
OnCalendar=*-*-* $SCHEDULE:00
Persistent=true

[Install]
WantedBy=timers.target
TIMEREOF

systemctl daemon-reload
systemctl enable --now restic-backup.timer
log "systemd timer enabled (daily at $SCHEDULE)"

section "5 — Run Initial Backup"
log "Running first backup..."
/usr/local/bin/restic-backup

section "Complete!"
echo ""
log "Restic is configured and running"
echo ""
echo "  Useful commands:"
echo "  restic -r $REPO snapshots             ← list backups"
echo "  restic -r $REPO ls latest             ← browse latest backup"
echo "  restic -r $REPO restore latest --target /tmp/restore  ← restore"
echo "  restic -r $REPO stats                 ← storage stats"
echo "  systemctl list-timers restic-backup   ← next run time"
echo ""
warn "IMPORTANT: Store your password safely! Without it, backups cannot be restored."
warn "Password file: /etc/restic/password"
