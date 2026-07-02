#!/usr/bin/env bash
# =============================================================================
# scripts/write-toolbox-banner.sh
# =============================================================================
# Appends the toolbox's web interface URLs to the console login screen
# (/etc/issue) and adds a first-login MOTD fragment listing them.
#
# Runs after apply-branding.sh (which owns the base /etc/issue warning
# banner -- this only appends to it, never overwrites) and after Semaphore,
# Webmin, and Homepage are all installed, so all three URLs are accurate.
#
# /etc/issue is displayed by agetty at the console login prompt, BEFORE
# authentication. It supports agetty's own escape codes -- \4 (IPv4
# address) and \n (nodename/hostname) here, not shell/printf escapes --
# evaluated fresh every time the prompt is drawn, not baked in at build
# time. That's why this works correctly for every clone of this template
# regardless of its actual assigned IP or hostname, with no per-clone
# scripting needed. See issue(5) for the full escape code reference.
#
# The MOTD fragment (/etc/update-motd.d/10-toolbox-services) is a real
# shell script, run fresh by run-parts on every login after authentication,
# so it resolves the IP/hostname directly rather than relying on escapes.
#
# Author  : IT-Architect-UK
# Repo    : https://github.com/IT-Architect-UK/monorepo
# =============================================================================

set -euo pipefail

log() { echo "[write-toolbox-banner] $*"; }

# ── Console login screen (/etc/issue) ─────────────────────────────────────────
log "Appending web interface URLs to /etc/issue..."
cat >> /etc/issue <<'EOF'
 Web Interfaces:
   Semaphore : http://\4/         (http://\n/)
   Webmin    : https://\4:10000/  (https://\n:10000/)
   Homepage  : http://\4:3002/    (http://\n:3002/)

EOF
log "/etc/issue updated."

# ── First-login MOTD fragment ─────────────────────────────────────────────────
# apply-branding.sh disables every MOTD fragment except its own 00-header
# ("chmod -x /etc/update-motd.d/*") to keep first-login output clean -- this
# fragment must explicitly chmod +x itself, and must run after that step.
log "Writing MOTD fragment /etc/update-motd.d/10-toolbox-services..."
cat > /etc/update-motd.d/10-toolbox-services <<'EOF'
#!/bin/sh
IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
HOST="$(hostname -f 2>/dev/null || hostname)"
printf "  Web Interfaces:\n"
printf "    Semaphore : http://%s/         (http://%s/)\n" "${IP}" "${HOST}"
printf "    Webmin    : https://%s:10000/  (https://%s:10000/)\n" "${IP}" "${HOST}"
printf "    Homepage  : http://%s:3002/    (http://%s:3002/)\n" "${IP}" "${HOST}"
printf "\n"
EOF
chmod +x /etc/update-motd.d/10-toolbox-services
log "MOTD fragment written."

log "Toolbox banner complete."
