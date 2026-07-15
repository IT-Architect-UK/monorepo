#!/usr/bin/env bash
# =============================================================================
# Deployment Toolbox — Post-Clone Bootstrap
# Run ONCE on the toolbox VM after cloning it from the Packer template.
# Turns a freshly cloned toolbox into a working provisioning server by
# configuring Semaphore via its API:
#
#   • Project    "Deployment Toolbox"
#   • Key Store  "None" key + toolbox SSH key (if present)
#   • Variable Group "Proxmox" — API connection details (secret-stored)
#   • Repository "monorepo" (this repo, cloned per task)
#   • Inventories "localhost" (for API-driven playbooks) and "lab-hosts"
#   • Job Template "Provision VM (Proxmox)" with Survey Variables
#   • Job Template "Deploy Vault Server"    with Survey Variables
#
# After this script completes you can provision VMs from the Semaphore UI:
#   http://<this-server>/  →  Task Templates  →  Provision VM (Proxmox)  →  Run
#
# Usage:
#   sudo /git/monorepo/automation/packer/builds/ubuntu-2404-automation-toolbox/scripts/bootstrap-toolbox.sh
#
# You will be prompted for:
#   1. The Semaphore admin password (set at image build time)
#   2. Proxmox API host (default read from environments/homelab.pkrvars.hcl)
#   3. Proxmox API credentials — an API token (recommended) or password
#
# To create a Proxmox API token (recommended over the root password):
#   Proxmox UI → Datacenter → Permissions → API Tokens → Add
#   (untick "Privilege Separation" for full rights, or scope as needed)
#   Enter it here as user (e.g. root@pam), token ID (e.g. automation) and secret.
#
# Idempotent: safe to re-run — existing objects are found by name and reused.
# Nothing sensitive is written to disk; secrets go into Semaphore's
# encrypted store and the API session token is revoked on exit.
#
# Author:            Darren Pilkington
# Version:           1.9
# Date:              02-07-2026
# =============================================================================

# First breath before strict mode: if this script ever dies, these two lines
# guarantee it can never do so silently — the banner proves it started, and
# the ERR trap names the exact line and command that killed it.
echo "[$(basename "${BASH_SOURCE[0]:-$0}")] starting as $(id -un 2>/dev/null || echo '?') in $(pwd)"
set -euo pipefail
trap 's=$?; echo "[$(basename "${BASH_SOURCE[0]:-$0}")] FATAL exit=$s at line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

# ─── Logging ─────────────────────────────────────────────────────────────────
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >&2; exit 1; }

SEMAPHORE_URL="http://127.0.0.1:3000"
COOKIE_JAR="$(mktemp)"
API_TOKEN=""

cleanup() {
    # Revoke the API token and remove the session cookie on any exit
    if [[ -n "${API_TOKEN}" ]]; then
        curl -fsS -X DELETE -H "Authorization: Bearer ${API_TOKEN}" \
            "${SEMAPHORE_URL}/api/user/tokens/${API_TOKEN}" >/dev/null 2>&1 || true
    fi
    rm -f "${COOKIE_JAR}"
}
trap cleanup EXIT

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ "${EUID}" -eq 0 ]] || fail "Run as root: sudo $0"
command -v curl &>/dev/null || fail "curl not found"
command -v jq   &>/dev/null || fail "jq not found"
systemctl is-active --quiet semaphore || fail "Semaphore service is not running (systemctl status semaphore)"

log "Waiting for the Semaphore API..."
for i in $(seq 1 30); do
    curl -fsS "${SEMAPHORE_URL}/api/ping" >/dev/null 2>&1 && break
    [[ $i -eq 30 ]] && fail "Semaphore API did not respond after 60s"
    sleep 2
done
log "Semaphore API is up."

# ─── Gather input ────────────────────────────────────────────────────────────
# Every value can be supplied via environment variables (that's how the build
# wrapper drives this script end-to-end); prompts appear only for whatever is
# missing. With BOOTSTRAP_NONINTERACTIVE=1, missing required values fail fast
# instead of prompting.
NONINTERACTIVE="${BOOTSTRAP_NONINTERACTIVE:-0}"
SEM_PASS="${SEMAPHORE_ADMIN_PASS:-}"
PVE_HOST="${PROXMOX_HOST:-}"
PVE_USER="${PROXMOX_USER:-}"
PVE_TOKEN_ID="${PROXMOX_TOKEN_ID:-}"
PVE_TOKEN_SECRET="${PROXMOX_TOKEN_SECRET:-}"
PVE_PASSWORD="${PROXMOX_PASSWORD:-}"
PVE_NODE="${PROXMOX_NODE:-}"
MGMT_SUBNET="${MGMT_SUBNET:-}"
# Default login for VMs deployed from goldens (passed from the build wrapper).
DEPLOY_ADMIN_USER="${DEPLOY_ADMIN_USER:-it-admin}"
DEPLOY_ADMIN_PASSWORD="${DEPLOY_ADMIN_PASSWORD:-}"

require_or_prompt_secret() { # varname prompt
    local -n ref="$1"
    [[ -n "${ref}" ]] && return 0
    [[ "${NONINTERACTIVE}" == "1" ]] && fail "$1 not provided (required in non-interactive mode)"
    read -r -s -p "$2: " ref; echo
}
default_or_prompt() { # varname prompt default
    local -n ref="$1"
    [[ -n "${ref}" ]] && return 0
    if [[ "${NONINTERACTIVE}" == "1" ]]; then ref="$3"; return 0; fi
    read -r -p "$2 [$3]: " ref
    ref="${ref:-$3}"
}

# Site defaults from the repo's single site file — nothing lab-specific here.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # own dir always exists
SITE_FILE="${SELF_DIR}/../../../environments/homelab.pkrvars.hcl"
site_val() {
    [[ -f "${SITE_FILE}" ]] || return 0
    grep -E "^\s*${1}\s*=" "${SITE_FILE}" | head -1 | sed -E 's/^[^=]*=\s*"?([^"#]*[^"# ])"?.*$/\1/'
}
SITE_HOST="$(site_val proxmox_url | sed -E 's#^https?://##; s#[:/].*$##')"
SITE_NODE="$(site_val proxmox_node)"

require_or_prompt_secret SEM_PASS "Semaphore admin password"
if [[ -n "${SITE_HOST}" ]]; then
    default_or_prompt PVE_HOST "Proxmox API host" "${SITE_HOST}"
else
    require_or_prompt_secret PVE_HOST "Proxmox API host"
fi
default_or_prompt PVE_USER "Proxmox API user" "$(site_val proxmox_username || true)"
PVE_USER="${PVE_USER:-root@pam}"
if [[ -z "${PVE_TOKEN_ID}" && -z "${PVE_PASSWORD}" && "${NONINTERACTIVE}" != "1" ]]; then
    read -r -p "Proxmox API token ID (leave empty to use password auth): " PVE_TOKEN_ID
    if [[ -n "${PVE_TOKEN_ID}" ]]; then
        read -r -s -p "Proxmox API token secret: " PVE_TOKEN_SECRET; echo
    else
        read -r -s -p "Proxmox password for ${PVE_USER}: " PVE_PASSWORD; echo
        warn "Password auth works, but an API token is the better long-term choice — see the header of this script."
    fi
fi
[[ -n "${PVE_TOKEN_SECRET}" || -n "${PVE_PASSWORD}" ]] || fail "No Proxmox credential provided (token or password)"
if [[ -n "${SITE_NODE}" ]]; then
    default_or_prompt PVE_NODE "Proxmox node name" "${SITE_NODE}"
else
    require_or_prompt_secret PVE_NODE "Proxmox node name"
fi

# WinRM build password for Windows golden images (optional — stored as a
# secret in the variable group so the win2025 Semaphore job works without
# manual UI setup; the build injects it into the unattended install)
WINRM_PW="${WINRM_PASSWORD:-}"
if [[ -z "${WINRM_PW}" && "${NONINTERACTIVE}" != "1" ]]; then
    read -r -s -p "WinRM password for Windows golden builds (Enter = skip): " WINRM_PW; echo
fi

# ─── Validate the Proxmox credential BEFORE storing it anywhere ──────────────
# A wrong user/token pairing (e.g. token owned by claude@pam entered against
# the default root@pam) poisons Semaphore jobs and the dashboard widget with
# 401s — caught on a real deployment. Probe /version and re-prompt on failure.
verify_pve() {
    if [[ -n "${PVE_TOKEN_ID}" ]]; then
        curl -fsSk --max-time 10 -H "Authorization: PVEAPIToken=${PVE_USER}!${PVE_TOKEN_ID}=${PVE_TOKEN_SECRET}"             "https://${PVE_HOST}:8006/api2/json/version" >/dev/null 2>&1
    else
        curl -fsSk --max-time 10 -X POST "https://${PVE_HOST}:8006/api2/json/access/ticket"             --data-urlencode "username=${PVE_USER}" --data-urlencode "password=${PVE_PASSWORD}" >/dev/null 2>&1
    fi
}
TRIES=0
until verify_pve; do
    TRIES=$(( TRIES + 1 ))
    warn "Proxmox rejected the credential (as ${PVE_USER}${PVE_TOKEN_ID:+!${PVE_TOKEN_ID}})."
    warn "Common cause: the user doesn't match the token's owner — a token created under"
    warn "claude@pam must be entered with user 'claude@pam', not the root@pam default."
    [[ "${NONINTERACTIVE}" == "1" || ${TRIES} -ge 3 ]] && fail "Proxmox credential validation failed"
    read -r -p "Proxmox API user [${PVE_USER}]: " u; PVE_USER="${u:-${PVE_USER}}"
    read -r -p "API token ID [${PVE_TOKEN_ID:-none}] (empty = keep): " t; PVE_TOKEN_ID="${t:-${PVE_TOKEN_ID}}"
    if [[ -n "${PVE_TOKEN_ID}" ]]; then
        read -r -s -p "API token secret: " ts; echo
        [[ -n "${ts}" ]] && PVE_TOKEN_SECRET="${ts}"
    else
        read -r -s -p "Password for ${PVE_USER}: " pw; echo
        [[ -n "${pw}" ]] && PVE_PASSWORD="${pw}"
    fi
done
log "Proxmox credential verified (${PVE_USER}${PVE_TOKEN_ID:+!${PVE_TOKEN_ID}})."

REPO_URL="https://github.com/IT-Architect-UK/monorepo.git"
REPO_BRANCH="main"

# ─── API helpers ─────────────────────────────────────────────────────────────
api() { # api METHOD PATH [JSON_BODY]
    local method="$1" path="$2" body="${3:-}"
    if [[ -n "${body}" ]]; then
        curl -fsS -X "${method}" \
            -H "Authorization: Bearer ${API_TOKEN}" \
            -H "Content-Type: application/json" -H "Accept: application/json" \
            -d "${body}" "${SEMAPHORE_URL}/api${path}"
    else
        curl -fsS -X "${method}" \
            -H "Authorization: Bearer ${API_TOKEN}" \
            -H "Accept: application/json" \
            "${SEMAPHORE_URL}/api${path}"
    fi
}

# find_id NAME JSON_ARRAY → prints id of object with .name==NAME, empty if none
find_id() { jq -r --arg n "$1" '[.[] | select(.name == $n)][0].id // empty'; }

# ─── Authenticate ────────────────────────────────────────────────────────────
log "Logging in to Semaphore..."
curl -fsS -c "${COOKIE_JAR}" -X POST \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    -d "$(jq -n --arg p "${SEM_PASS}" '{auth: "admin", password: $p}')" \
    "${SEMAPHORE_URL}/api/auth/login" >/dev/null \
    || fail "Login failed — wrong admin password?"

API_TOKEN=$(curl -fsS -b "${COOKIE_JAR}" -X POST \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    "${SEMAPHORE_URL}/api/user/tokens" | jq -r '.id')
[[ -n "${API_TOKEN}" && "${API_TOKEN}" != "null" ]] || fail "Could not obtain an API token"

# Persistent token for the deploy playbooks to register hosts in per-OS
# inventories. NOT revoked on exit (the API_TOKEN above is only for this run).
# Stored as a secret in the Proxmox variable group below.
DEPLOY_TOKEN=$(curl -fsS -b "${COOKIE_JAR}" -X POST \
    -H "Content-Type: application/json" -H "Accept: application/json" \
    "${SEMAPHORE_URL}/api/user/tokens" | jq -r '.id' 2>/dev/null) || DEPLOY_TOKEN=""
[[ -n "${DEPLOY_TOKEN}" && "${DEPLOY_TOKEN}" != "null" ]] || { DEPLOY_TOKEN=""; warn "Could not mint a persistent deploy token — VM deploys will not auto-register in inventories."; }
log "Authenticated."

# ─── 1. Project ──────────────────────────────────────────────────────────────
PROJECT_NAME="Deployment Toolbox"
PROJECT_ID=$(api GET /projects | find_id "${PROJECT_NAME}")
if [[ -z "${PROJECT_ID}" ]]; then
    PROJECT_ID=$(api POST /projects \
        "$(jq -n --arg n "${PROJECT_NAME}" '{name: $n, alert: false}')" | jq -r '.id')
    log "Project '${PROJECT_NAME}' created (id ${PROJECT_ID})"
else
    log "Project '${PROJECT_NAME}' already exists (id ${PROJECT_ID})"
fi
P="/project/${PROJECT_ID}"

# ─── 2. Key Store ────────────────────────────────────────────────────────────
KEYS_JSON=$(api GET "${P}/keys")
NONE_KEY_ID=$(echo "${KEYS_JSON}" | find_id "None")
if [[ -z "${NONE_KEY_ID}" ]]; then
    NONE_KEY_ID=$(api POST "${P}/keys" \
        "$(jq -n --argjson pid "${PROJECT_ID}" '{name: "None", type: "none", project_id: $pid}')" | jq -r '.id')
    log "Key 'None' created (id ${NONE_KEY_ID})"
else
    log "Key 'None' already exists (id ${NONE_KEY_ID})"
fi

SSH_KEY_FILE="/home/toolbox/.ssh/id_ed25519"
SSH_KEY_ID=$(echo "${KEYS_JSON}" | find_id "toolbox-ssh")
if [[ -z "${SSH_KEY_ID}" && -f "${SSH_KEY_FILE}" ]]; then
    SSH_KEY_ID=$(api POST "${P}/keys" \
        "$(jq -n --argjson pid "${PROJECT_ID}" --rawfile k "${SSH_KEY_FILE}" \
            '{name: "toolbox-ssh", type: "ssh", project_id: $pid, ssh: {login: "toolbox", private_key: $k}}')" | jq -r '.id')
    log "Key 'toolbox-ssh' created from ${SSH_KEY_FILE} (id ${SSH_KEY_ID})"
elif [[ -n "${SSH_KEY_ID}" ]]; then
    log "Key 'toolbox-ssh' already exists (id ${SSH_KEY_ID})"
else
    warn "No SSH key at ${SSH_KEY_FILE} — remote-host inventories will need a key added manually."
    SSH_KEY_ID="${NONE_KEY_ID}"
fi

# Dedicated provisioning keypair: the toolbox injects the PUBLIC key into
# every VM it provisions (cloud-init) and keeps the PRIVATE key in the Key
# Store, so follow-up playbooks (Deploy Vault, baselines) can connect
# without any manual key juggling.
PROV_KEY_DIR="/var/lib/semaphore/.ssh"
PROV_KEY_FILE="${PROV_KEY_DIR}/provisioning_ed25519"
if [[ ! -f "${PROV_KEY_FILE}" ]]; then
    mkdir -p "${PROV_KEY_DIR}"
    ssh-keygen -t ed25519 -N "" -C "toolbox-provisioning" -f "${PROV_KEY_FILE}" -q
    chown -R semaphore:semaphore "${PROV_KEY_DIR}" 2>/dev/null || true
    chmod 700 "${PROV_KEY_DIR}"; chmod 600 "${PROV_KEY_FILE}"
    log "Provisioning SSH keypair generated (${PROV_KEY_FILE})"
fi
PROV_PUBKEY="$(cat "${PROV_KEY_FILE}.pub")"
PROV_KEY_ID=$(echo "${KEYS_JSON}" | find_id "provisioning-ssh")
if [[ -z "${PROV_KEY_ID}" ]]; then
    PROV_KEY_ID=$(api POST "${P}/keys"         "$(jq -n --argjson pid "${PROJECT_ID}" --rawfile k "${PROV_KEY_FILE}"             '{name: "provisioning-ssh", type: "ssh", project_id: $pid, ssh: {login: "", private_key: $k}}')" | jq -r '.id')
    log "Key 'provisioning-ssh' created (id ${PROV_KEY_ID}) — private key stays in the Key Store"
else
    log "Key 'provisioning-ssh' already exists (id ${PROV_KEY_ID})"
fi

# ─── 3. Variable Group (Proxmox connection) ──────────────────────────────────
ENV_ID=$(api GET "${P}/environment" | find_id "Proxmox")
if [[ -z "${ENV_ID}" ]]; then
    ENV_BODY=$(jq -n \
        --argjson pid "${PROJECT_ID}" \
        --arg host "${PVE_HOST}" --arg user "${PVE_USER}" --arg node "${PVE_NODE}" \
        --arg tid "${PVE_TOKEN_ID}" --arg tsec "${PVE_TOKEN_SECRET}" --arg pw "${PVE_PASSWORD}" \
        --arg pub "${PROV_PUBKEY}" --arg winrm "${WINRM_PW}" \
        --arg surl "${SEMAPHORE_URL}" --arg spid "${PROJECT_ID}" --arg dtok "${DEPLOY_TOKEN}" \
        --arg dauser "${DEPLOY_ADMIN_USER}" --arg dapass "${DEPLOY_ADMIN_PASSWORD}" \
        '{
          name: "Proxmox", project_id: $pid, json: "{}",
          env: ({PROXMOX_HOST: $host, PROXMOX_USER: $user, PROXMOX_NODE: $node, PROXMOX_TOKEN_ID: $tid, PROVISION_SSH_PUBKEY: $pub, SEMAPHORE_URL: $surl, SEMAPHORE_PROJECT_ID: $spid, DEPLOY_ADMIN_USER: $dauser} | tojson),
          secrets: ([
            (if $tsec  != "" then {type: "env", name: "PROXMOX_TOKEN_SECRET", secret: $tsec,  operation: "create"} else empty end),
            (if $pw    != "" then {type: "env", name: "PROXMOX_PASSWORD",     secret: $pw,    operation: "create"} else empty end),
            (if $winrm != "" then {type: "env", name: "WINRM_PASSWORD",       secret: $winrm, operation: "create"} else empty end),
            (if $dtok  != "" then {type: "env", name: "SEMAPHORE_API_TOKEN",  secret: $dtok,  operation: "create"} else empty end),
            (if $dapass != "" then {type: "env", name: "DEPLOY_ADMIN_PASSWORD", secret: $dapass, operation: "create"} else empty end)
          ])
        }')
    ENV_ID=$(api POST "${P}/environment" "${ENV_BODY}" | jq -r '.id')
    log "Variable group 'Proxmox' created (id ${ENV_ID}) — secrets stored encrypted in Semaphore"
else
    log "Variable group 'Proxmox' already exists (id ${ENV_ID}) — credentials NOT overwritten (edit in UI if they changed)"
fi

# ─── 4. Repository ───────────────────────────────────────────────────────────
REPO_ID=$(api GET "${P}/repositories" | find_id "monorepo")
if [[ -z "${REPO_ID}" ]]; then
    REPO_ID=$(api POST "${P}/repositories" \
        "$(jq -n --argjson pid "${PROJECT_ID}" --argjson kid "${NONE_KEY_ID}" \
            --arg url "${REPO_URL}" --arg br "${REPO_BRANCH}" \
            '{name: "monorepo", project_id: $pid, git_url: $url, git_branch: $br, ssh_key_id: $kid}')" | jq -r '.id')
    log "Repository 'monorepo' created (id ${REPO_ID})"
else
    log "Repository 'monorepo' already exists (id ${REPO_ID})"
fi

# ─── 5. Inventories ──────────────────────────────────────────────────────────
INV_JSON=$(api GET "${P}/inventory")
LOCAL_INV_ID=$(echo "${INV_JSON}" | find_id "localhost")
if [[ -z "${LOCAL_INV_ID}" ]]; then
    LOCAL_INV_ID=$(api POST "${P}/inventory" \
        "$(jq -n --argjson pid "${PROJECT_ID}" --argjson kid "${PROV_KEY_ID}" \
            '{name: "localhost", project_id: $pid, type: "static", ssh_key_id: $kid,
              inventory: "localhost ansible_connection=local ansible_python_interpreter=/usr/bin/python3"}')" | jq -r '.id')
    log "Inventory 'localhost' created (id ${LOCAL_INV_ID})"
else
    log "Inventory 'localhost' already exists (id ${LOCAL_INV_ID})"
fi

LAB_INV_ID=$(echo "${INV_JSON}" | find_id "lab-hosts")
if [[ -z "${LAB_INV_ID}" ]]; then
    LAB_INV_ID=$(api POST "${P}/inventory" \
        "$(jq -n --argjson pid "${PROJECT_ID}" --argjson kid "${SSH_KEY_ID}" --argjson rid "${REPO_ID}" \
            '{name: "lab-hosts", project_id: $pid, type: "file", ssh_key_id: $kid, repository_id: $rid,
              inventory: "automation/ansible/inventory/hosts.yml"}')" | jq -r '.id')
    log "Inventory 'lab-hosts' created (id ${LAB_INV_ID})"
else
    log "Inventory 'lab-hosts' already exists (id ${LAB_INV_ID})"
fi

# Per-OS host inventories — deploys register their new VM into the matching one,
# so customisation templates can later target a whole OS group. Static (stored
# in Semaphore); the Deploy VM templates append hosts via the API.
seed_inv() { # seed_inv <name> — echoes the id (logs to stderr)
    local name="$1" iid
    iid=$(echo "${INV_JSON}" | find_id "${name}") || iid=""
    if [[ -z "${iid}" ]]; then
        iid=$(api POST "${P}/inventory" "$(jq -n --argjson pid "${PROJECT_ID}" --argjson kid "${PROV_KEY_ID}" --arg n "${name}" \
            '{name:$n, project_id:$pid, type:"static", ssh_key_id:$kid,
              inventory:("# " + $n + " — hosts are added automatically by the Deploy VM templates\n")}')" 2>/dev/null | jq -r '.id // empty') || iid=""
        [[ -n "${iid}" ]] && echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO]  Inventory '${name}' created (id ${iid})" >&2 \
                          || echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN]  Could not create inventory '${name}'" >&2
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO]  Inventory '${name}' already exists (id ${iid})" >&2
    fi
    echo "${iid}"
}
INV_U2404_ID=$(seed_inv "Ubuntu 24.04 Hosts")
INV_U2604_ID=$(seed_inv "Ubuntu 26.04 Hosts")
INV_WIN_ID=$(seed_inv "Windows Hosts")
# Default-build group: every Linux VM deployed from a template is added here
# (unless the deploy survey opts out) so it picks up — and can re-pick-up — the
# default build via the "Apply Baseline (Linux)" template.
INV_BASELINE_ID=$(seed_inv "Linux Baseline")

# ─── 6. Job Templates ────────────────────────────────────────────────────────
TPL_JSON=$(api GET "${P}/templates")

# Views group templates in the Semaphore sidebar. Created before the templates
# so each can be filed under one. Best-effort: if this Semaphore predates Views,
# the ids stay empty and templates simply show ungrouped. NB views key on
# 'title' (not 'name'), so find_id (which matches name) can't be used here.
VIEWS_JSON=$(api GET "${P}/views" 2>/dev/null || echo '[]')
seed_view() { # seed_view <title> <position> — echoes the id (logs to stderr)
    local title="$1" pos="$2" vid
    vid=$(echo "${VIEWS_JSON}" | jq -r --arg t "${title}" '[.[] | select(.title == $t)][0].id // empty' 2>/dev/null) || vid=""
    if [[ -z "${vid}" ]]; then
        vid=$(api POST "${P}/views" "$(jq -n --arg t "${title}" --argjson pid "${PROJECT_ID}" --argjson pos "${pos}" \
              '{title: $t, project_id: $pid, position: $pos}')" 2>/dev/null | jq -r '.id // empty') || vid=""
        [[ -n "${vid}" ]] && echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO]  View '${title}' created (id ${vid})" >&2 \
                          || echo "$(date '+%Y-%m-%d %H:%M:%S') [WARN]  Could not create view '${title}' — its templates will be ungrouped" >&2
    else
        echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO]  View '${title}' already exists (id ${vid})" >&2
    fi
    echo "${vid}"
}
VIEW_TOOLBOX_ID=$(seed_view "Deployment Toolbox" 1)
VIEW_LINUX_ID=$(seed_view "Linux Tasks" 2)
VIEW_WINDOWS_ID=$(seed_view "Windows Tasks" 3)
VIEW_ROLES_ID=$(seed_view "Server Roles" 4)

# POST a template, adding view_id only when a valid (>0) view id is supplied,
# so template creation is unaffected if views weren't available.
post_template() { # post_template <view_id> <template-json> — create OR update by name (upsert)
    local vid="$1" json="$2" name tid
    name=$(echo "${json}" | jq -r '.name')
    if [[ -n "${vid}" && "${vid}" != "0" ]]; then
        json=$(echo "${json}" | jq -c --argjson v "${vid}" '. + {view_id: $v}')
    fi
    tid=$(echo "${TPL_JSON}" | find_id "${name}")
    if [[ -z "${tid}" ]]; then
        api POST "${P}/templates" "${json}"
    else
        # Update in place so survey/args/description changes propagate without
        # deleting the template. PUT returns no body, so echo the id ourselves.
        api PUT "${P}/templates/${tid}" "$(echo "${json}" | jq -c --argjson id "${tid}" '. + {id: $id}')" >/dev/null 2>&1 || true
        echo "{\"id\": ${tid}}"
    fi
}

PROV_TPL_ID=$(post_template "${VIEW_TOOLBOX_ID:-0}" "$(jq -n \
        --argjson pid "${PROJECT_ID}" --argjson inv "${LOCAL_INV_ID}" \
        --argjson rid "${REPO_ID}" --argjson eid "${ENV_ID}" \
        '{
          project_id: $pid, name: "Provision VM (Proxmox)", app: "ansible",
          playbook: "automation/ansible/playbooks/provision-vm.yml",
          inventory_id: $inv, repository_id: $rid, environment_id: $eid,
          arguments: "[]", type: "",
          description: "Clone a Proxmox template into a new VM, size it, and start it.",
          survey_vars: [
            {name: "vm_name",      title: "VM name (also the hostname)",    type: "",    required: true},
            {name: "vm_template",  title: "Proxmox template to clone",      type: "",    required: true},
            {name: "apply_standard", title: "Apply the standard build? (branding, firewall, fail2ban, Webmin — see group_vars/standard.yml)", type: "enum", required: true,
             values: [{name: "Yes", value: "true"}, {name: "No", value: "false"}]},
            {name: "vm_user",      title: "Login account to create",        type: "",    required: false},
            {name: "vm_password",  title: "Password for that account",      type: "secret", required: false},
            {name: "vm_ssh_key",   title: "SSH public key for that account", type: "",   required: false},
            {name: "vm_vcpu",      title: "vCPU count (default 2)",         type: "int", required: false},
            {name: "vm_memory_mb", title: "Memory MB (default 4096)",       type: "int", required: false},
            {name: "vm_disk_gb",   title: "Grow OS disk to GB (0 = keep)",  type: "int", required: false},
            {name: "vm_vlan_tag",  title: "VLAN tag (empty = keep)",        type: "",    required: false}
          ]
        }')" | jq -r '.id')
log "Job template 'Provision VM (Proxmox)' upserted (id ${PROV_TPL_ID})"

VAULT_TPL_ID=$(echo "${TPL_JSON}" | find_id "Deploy Vault Server")
if [[ -z "${VAULT_TPL_ID}" ]]; then
    VAULT_TPL_ID=$(post_template "${VIEW_ROLES_ID:-0}" "$(jq -n \
        --argjson pid "${PROJECT_ID}" --argjson inv "${LOCAL_INV_ID}" \
        --argjson rid "${REPO_ID}" --argjson eid "${ENV_ID}" \
        '{
          project_id: $pid, name: "Deploy Vault Server", app: "ansible",
          playbook: "automation/ansible/playbooks/deploy-vault.yml",
          inventory_id: $inv, repository_id: $rid, environment_id: $eid,
          arguments: "[]", type: "",
          description: "Install HashiCorp Vault on a freshly provisioned VM. Run Provision VM first.",
          survey_vars: [
            {name: "vault_host",     title: "Target server IP/FQDN",          type: "", required: true},
            {name: "vault_ssh_user", title: "SSH user (default sysadmin)",    type: "", required: false}
          ]
        }')" | jq -r '.id')
    log "Job template 'Deploy Vault Server' created (id ${VAULT_TPL_ID})"
else
    log "Job template 'Deploy Vault Server' already exists (id ${VAULT_TPL_ID})"
fi

GOLD_TPL_ID=$(echo "${TPL_JSON}" | find_id "Build Golden Image — Ubuntu 24.04")
if [[ -z "${GOLD_TPL_ID}" ]]; then
    GOLD_TPL_ID=$(post_template "${VIEW_TOOLBOX_ID:-0}" "$(jq -n \
        --argjson pid "${PROJECT_ID}" --argjson inv "${LOCAL_INV_ID}" \
        --argjson rid "${REPO_ID}" --argjson eid "${ENV_ID}" \
        '{
          project_id: $pid, name: "Build Golden Image — Ubuntu 24.04", app: "bash",
          playbook: "automation/packer/builds/ubuntu-2404-proxmox/build-ubuntu-2404-proxmox.sh",
          inventory_id: $inv, repository_id: $rid, environment_id: $eid,
          arguments: "[]", type: "",
          description: "Packer-build a fresh, patched Ubuntu 24.04 template on Proxmox. Add a Schedule for monthly golden-image refreshes."
        }')" | jq -r '.id')
    log "Job template 'Build Golden Image — Ubuntu 24.04' created (id ${GOLD_TPL_ID})"
else
    log "Job template 'Build Golden Image — Ubuntu 24.04' already exists (id ${GOLD_TPL_ID})"
fi

for GOLD in "Build Golden Image — Ubuntu 26.04|automation/packer/builds/ubuntu-2604-proxmox/build-ubuntu-2604-proxmox.sh|Packer-build a fresh Ubuntu 26.04 template on Proxmox." \
            "Build Golden Image — Windows 2025|automation/packer/builds/win2025-proxmox/build-win2025-proxmox.sh|Packer-build a Windows Server 2025 template. Requires the Windows ISO pre-uploaded and WINRM_PASSWORD in the variable group."; do
    G_NAME="${GOLD%%|*}"; G_REST="${GOLD#*|}"; G_PLAY="${G_REST%%|*}"; G_DESC="${G_REST#*|}"
    G_VIEW="${VIEW_TOOLBOX_ID:-0}"   # golden image builds live under Deployment Toolbox
    G_ID=$(echo "${TPL_JSON}" | find_id "${G_NAME}")
    if [[ -z "${G_ID}" ]]; then
        G_ID=$(post_template "${G_VIEW:-0}" "$(jq -n \
            --argjson pid "${PROJECT_ID}" --argjson inv "${LOCAL_INV_ID}" \
            --argjson rid "${REPO_ID}" --argjson eid "${ENV_ID}" \
            --arg name "${G_NAME}" --arg play "${G_PLAY}" --arg desc "${G_DESC}" \
            '{project_id: $pid, name: $name, app: "bash", playbook: $play,
              inventory_id: $inv, repository_id: $rid, environment_id: $eid,
              arguments: "[]", type: "", description: $desc}')" | jq -r '.id')
        log "Job template '${G_NAME}' created (id ${G_ID})"
    else
        log "Job template '${G_NAME}' already exists (id ${G_ID})"
    fi
    case "${G_NAME}" in
        *"26.04"*)   GOLD26_TPL_ID="${G_ID}"  ;;
        *"Windows"*) GOLDWIN_TPL_ID="${G_ID}" ;;
    esac
done

SEED_TPL() { # SEED_TPL <name> <playbook> <description> <survey-json>
    local T_ID
    T_ID=$(post_template "${VIEW_LINUX_ID:-0}" "$(jq -n \
        --argjson pid "${PROJECT_ID}" --argjson inv "${LOCAL_INV_ID}" \
        --argjson rid "${REPO_ID}" --argjson eid "${ENV_ID}" \
        --arg name "$1" --arg play "$2" --arg desc "$3" --argjson survey "$4" \
        '{project_id: $pid, name: $name, app: "ansible", playbook: $play,
          inventory_id: $inv, repository_id: $rid, environment_id: $eid,
          arguments: "[]", type: "", description: $desc, survey_vars: $survey}')" | jq -r '.id')
    log "Job template '$1' upserted (id ${T_ID})"
}

TARGET_FIELDS='[{"name":"target_host","title":"Server IP/FQDN","type":"","required":true},
                {"name":"target_ssh_user","title":"SSH user (default sysadmin)","type":"","required":false}]'
YESNO='{"type":"enum","required":true,"values":[{"name":"Yes","value":"true"},{"name":"No","value":"false"}]}'

SEED_TPL "ITA Linux Customisations" \
    "automation/ansible/playbooks/ita-linux-customisations.yml" \
    "Subjective OS settings, each individually chosen: branding, IPv6 policy, timezone. Firewall/fail2ban/apps have their own templates." \
    "$(jq -n --argjson t "${TARGET_FIELDS}" --argjson yn "${YESNO}" \
        '$t + [($yn + {name:"apply_branding", title:"Apply IT-Architect branding?"}),
               ($yn + {name:"disable_ipv6",  title:"Disable IPv6?"}),
               {name:"set_timezone", title:"Timezone (e.g. Europe/London; empty = leave)", type:"", required:false}]')"

SEED_TPL "Configure IPTables Firewall" \
    "automation/ansible/playbooks/configure-iptables.yml" \
    "Apply the iptables ruleset. Leave subnet empty = baseline (private ranges allowed); set it = STRICT (only listed ports from that subnet)." \
    "$(jq -n --argjson t "${TARGET_FIELDS}" \
        '$t + [{name:"mgmt_subnets", title:"Management subnet(s) for STRICT mode (empty = baseline)", type:"", required:false},
               {name:"allowed_tcp_ports", title:"Allowed TCP ports in strict mode (e.g. 22,80,443)", type:"", required:false}]')"

SEED_TPL "Configure Fail2Ban" \
    "automation/ansible/playbooks/configure-fail2ban.yml" \
    "Install and configure fail2ban SSH brute-force protection." \
    "$(jq -n --argjson t "${TARGET_FIELDS}" \
        '$t + [{name:"fail2ban_maxretry", title:"Failed attempts before ban (default 5)", type:"int", required:false},
               {name:"fail2ban_bantime", title:"Ban duration seconds (default 3600)", type:"int", required:false}]')"

WEBMIN_TPL_ID=$(post_template "${VIEW_LINUX_ID:-0}" "$(jq -n \
        --argjson pid "${PROJECT_ID}" --argjson inv "${LOCAL_INV_ID}" \
        --argjson rid "${REPO_ID}" --argjson eid "${ENV_ID}" \
        '{project_id: $pid, name: "Deploy Webmin", app: "ansible",
          playbook: "automation/ansible/playbooks/deploy-webmin.yml",
          inventory_id: $inv, repository_id: $rid, environment_id: $eid,
          arguments: "[]", type: "",
          description: "Install Webmin (web-based server admin, port 10000) on any provisioned server.",
          survey_vars: [
            {name: "target_host",     title: "Server IP/FQDN",              type: "", required: true},
            {name: "target_ssh_user", title: "SSH user (default sysadmin)", type: "", required: false}
          ]}')" | jq -r '.id')
log "Job template 'Deploy Webmin' upserted (id ${WEBMIN_TPL_ID})"

# The default build as a re-runnable template, bound to the Linux Baseline
# inventory (the group Deploy VM adds hosts to). Leave the survey blank to apply
# to every baseline host, or set target_host to re-apply to a single server.
BASELINE_TPL_ID=$(post_template "${VIEW_LINUX_ID:-0}" "$(jq -n \
        --argjson pid "${PROJECT_ID}" --argjson inv "${INV_BASELINE_ID:-0}" \
        --argjson rid "${REPO_ID}" --argjson eid "${ENV_ID}" \
        '{project_id: $pid, name: "Apply Baseline (Linux)", app: "ansible",
          playbook: "automation/ansible/playbooks/server-baseline.yml",
          inventory_id: $inv, repository_id: $rid, environment_id: $eid,
          arguments: "[]", type: "",
          description: "Apply the default build (baseline + Webmin) to the Linux Baseline group. Blank survey = all baseline hosts; set a host to re-apply to one server.",
          survey_vars: [
            {name: "target_host",     title: "Single Server IP/FQDN (blank = all hosts in Linux Baseline)", type: "", required: false},
            {name: "target_ssh_user", title: "SSH user for single-host mode (default it-admin)",            type: "", required: false}
          ]}')" | jq -r '.id')
log "Job template 'Apply Baseline (Linux)' upserted (id ${BASELINE_TPL_ID})"

PROBE_TPL_ID=$(echo "${TPL_JSON}" | find_id "Diagnostics — Task Probe")
if [[ -z "${PROBE_TPL_ID}" ]]; then
    PROBE_TPL_ID=$(post_template "${VIEW_TOOLBOX_ID:-0}" "$(jq -n \
        --argjson pid "${PROJECT_ID}" --argjson inv "${LOCAL_INV_ID}" \
        --argjson rid "${REPO_ID}" --argjson eid "${ENV_ID}" \
        '{project_id: $pid, name: "Diagnostics — Task Probe", app: "bash",
          playbook: "automation/packer/scripts/task-probe.sh",
          inventory_id: $inv, repository_id: $rid, environment_id: $eid,
          arguments: "[]", type: "",
          description: "Prints the task execution context (user, paths, env var names). Run when any job misbehaves — its output is always safe to share."}')" | jq -r '.id')
    log "Job template 'Diagnostics — Task Probe' created (id ${PROBE_TPL_ID})"
else
    log "Job template 'Diagnostics — Task Probe' already exists (id ${PROBE_TPL_ID})"
fi

# ─── 6b. Per-OS "Deploy VM" templates ────────────────────────────────────────
# One-click deploy from each golden: clone by its fixed VMID, set the name and
# (Linux) a static IP or DHCP, start it, and register it in the per-OS
# inventory. Customisation is run separately against those inventories.
# golden VMIDs match the golden build defaults (variables.pkr.hcl):
#   9004 = Ubuntu 24.04, 9006 = Ubuntu 26.04, 9003 = Windows 2025.
SURVEY_IP='[
  {"name":"vm_name","title":"VM name (also the hostname)","type":"","required":true},
  {"name":"apply_standard","title":"Apply the default build (baseline + Webmin) and add to the Linux Baseline group? Leave Yes unless you want a bare VM.","type":"enum","required":false,"default_value":"true","values":[{"name":"Yes","value":"true"},{"name":"No","value":"false"}]},
  {"name":"vm_ip_cidr","title":"IP address: blank = DHCP, or static CIDR e.g. 192.168.4.50/24","type":"","required":false},
  {"name":"vm_gateway","title":"Gateway (blank = .1 of the subnet)","type":"","required":false},
  {"name":"vm_vlan_tag","title":"VLAN tag (blank = template default)","type":"","required":false},
  {"name":"vm_user","title":"Login account to create (e.g. it-admin; blank = none)","type":"","required":false},
  {"name":"vm_password","title":"Password for that account","type":"secret","required":false},
  {"name":"vm_ssh_key","title":"Extra SSH public key for the account (the toolbox key is always added)","type":"","required":false},
  {"name":"vm_vcpu","title":"vCPU count (blank = 2)","type":"int","required":false},
  {"name":"vm_memory_mb","title":"Memory MB (blank = 4096)","type":"int","required":false},
  {"name":"vm_disk_gb","title":"Grow OS disk to GB (0 = keep template size)","type":"int","required":false}
]'
SURVEY_NOIP='[
  {"name":"vm_name","title":"VM name (also the hostname)","type":"","required":true},
  {"name":"vm_user","title":"Login account to create (e.g. it-admin; blank = none)","type":"","required":false},
  {"name":"vm_password","title":"Password for that account","type":"secret","required":false},
  {"name":"vm_vlan_tag","title":"VLAN tag (blank = template default)","type":"","required":false},
  {"name":"vm_vcpu","title":"vCPU count (blank = 4)","type":"int","required":false},
  {"name":"vm_memory_mb","title":"Memory MB (blank = 8192)","type":"int","required":false},
  {"name":"vm_disk_gb","title":"Grow OS disk to GB (0 = keep template size)","type":"int","required":false},
  {"name":"vm_data_disk_gb","title":"Data disk size GB for D: (Apps & Data); 0 = none","type":"int","required":false,"default_value":"50"}
]'

SEED_DEPLOY() { # SEED_DEPLOY <name> <golden_vmid> <inv_id> <os_label> <cloudinit_ip> <survey_json> <desc> [baseline_inv_id]
    local name="$1" gvmid="$2" invid="$3" oslabel="$4" ciip="$5" survey="$6" desc="$7" binvid="${8:-0}" osdisk="${9:-scsi0}" cibus="${10:-scsi1}" citype="${11:-}" tid args
    args=$(jq -nc --arg g "${gvmid}" --arg i "${invid:-0}" --arg o "${oslabel}" --arg c "${ciip}" --arg b "${binvid:-0}" --arg d "${osdisk}" --arg cb "${cibus}" --arg ct "${citype}" \
        '["-e","golden_vmid=\($g)","-e","register_inventory_id=\($i)","-e","baseline_inventory_id=\($b)","-e","os_label=\($o)","-e","cloudinit_ip=\($c)","-e","os_disk=\($d)","-e","ci_bus=\($cb)","-e","ci_type=\($ct)"]')
    tid=$(post_template "${VIEW_TOOLBOX_ID:-0}" "$(jq -n \
        --argjson pid "${PROJECT_ID}" --argjson inv "${LOCAL_INV_ID}" \
        --argjson rid "${REPO_ID}" --argjson eid "${ENV_ID}" \
        --arg name "${name}" --arg args "${args}" --argjson survey "${survey}" --arg desc "${desc}" \
        '{project_id:$pid, name:$name, app:"ansible",
          playbook:"automation/ansible/playbooks/provision-vm.yml",
          inventory_id:$inv, repository_id:$rid, environment_id:$eid,
          arguments:$args, type:"", survey_vars:$survey, description:$desc}')" | jq -r '.id // empty')
    [[ -n "${tid}" ]] && log "Job template '${name}' upserted (id ${tid})" \
                      || warn "Could not upsert job template '${name}'"
}
SEED_DEPLOY "Deploy Ubuntu 24.04 VM" 9004 "${INV_U2404_ID}" ubuntu-2404 true  "${SURVEY_IP}" \
    "Clone the Ubuntu 24.04 golden into a new VM (name + optional static IP), start it, register it in the Ubuntu 24.04 Hosts inventory, and apply the default build unless opted out." \
    "${INV_BASELINE_ID}"
SEED_DEPLOY "Deploy Ubuntu 26.04 VM" 9006 "${INV_U2604_ID}" ubuntu-2604 true  "${SURVEY_IP}" \
    "Clone the Ubuntu 26.04 golden into a new VM (name + optional static IP), start it, register it in the Ubuntu 26.04 Hosts inventory, and apply the default build unless opted out." \
    "${INV_BASELINE_ID}"
SEED_DEPLOY "Deploy Windows 2025 VM" 9003 "${INV_WIN_ID}"  windows     true  "${SURVEY_NOIP}" \
    "Clone the Windows Server 2025 golden into a new VM, attach a ConfigDrive2 drive so cloudbase-init applies hostname/user/network on first boot, start it, and register it in the Windows Hosts inventory." \
    "" "sata0" "sata1" "configdrive2"

# ─── Summary ─────────────────────────────────────────────────────────────────
# ─── 7. Finalise the Homepage dashboard ──────────────────────────────────────
# Homepage widget credentials live in an --env-file. Two rules matter here:
#   • NEVER truncate the env file — set each key IN PLACE. An earlier version
#     used `cat >` for the Proxmox creds, which deleted the Portainer key line
#     so the widget never got a key.
#   • `docker restart` does NOT re-read an --env-file. The container must be
#     RECREATED to pick up new values. So we write every credential first, then
#     recreate the homepage container once at the end (section 7c).
HOMEPAGE_CONFIG="/opt/homepage/config"
HOMEPAGE_ENV="/opt/homepage/.env.homepage"
SERVER_IP=$(hostname -I | awk '{print $1}')
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
HOMEPAGE_INSTALL="${REPO_ROOT}/applications/homepage/install-homepage.sh"
[[ -f "${HOMEPAGE_INSTALL}" ]] || HOMEPAGE_INSTALL="/git/monorepo/applications/homepage/install-homepage.sh"
PORTAINER_INSTALL="${REPO_ROOT}/containers/portainer/install-portainer.sh"
[[ -f "${PORTAINER_INSTALL}" ]] || PORTAINER_INSTALL="/git/monorepo/containers/portainer/install-portainer.sh"

# Set KEY=VALUE in an env file without disturbing other lines. Uses grep-out +
# append (not sed) so values containing +, / or = never trip a delimiter.
set_env_kv() { # set_env_kv FILE KEY VALUE
    local file="$1" key="$2" val="$3" tmp
    touch "${file}"; chmod 600 "${file}"
    tmp="$(mktemp)"
    grep -v "^${key}=" "${file}" > "${tmp}" 2>/dev/null || true
    printf '%s=%s\n' "${key}" "${val}" >> "${tmp}"
    cat "${tmp}" > "${file}"; rm -f "${tmp}"
}

if [[ -d "${HOMEPAGE_CONFIG}" ]]; then
    if grep -q "toolbox.lab.local" "${HOMEPAGE_CONFIG}/services.yaml" 2>/dev/null; then
        sed -i "s/toolbox\.lab\.local/${SERVER_IP}/g" "${HOMEPAGE_CONFIG}/services.yaml"
        log "Homepage: placeholder hostnames replaced with ${SERVER_IP}"
    fi
    if grep -q "PROXMOX-HOST-PLACEHOLDER" "${HOMEPAGE_CONFIG}/services.yaml" 2>/dev/null; then
        sed -i "s/PROXMOX-HOST-PLACEHOLDER/${PVE_HOST}/g" "${HOMEPAGE_CONFIG}/services.yaml"
        log "Homepage: Proxmox tile pointed at ${PVE_HOST}"
    fi
    if [[ -n "${PVE_TOKEN_ID}" ]]; then
        # Proxmox widget auth: username = user@realm!tokenid, password = secret.
        set_env_kv "${HOMEPAGE_ENV}" HOMEPAGE_VAR_PROXMOX_USER "${PVE_USER}!${PVE_TOKEN_ID}"
        set_env_kv "${HOMEPAGE_ENV}" HOMEPAGE_VAR_PROXMOX_PASS "${PVE_TOKEN_SECRET}"
        set_env_kv "${HOMEPAGE_ENV}" HOMEPAGE_VAR_PROXMOX_NODE "${PVE_NODE}"
        log "Homepage: Proxmox widget credentials written (token auth)"
    else
        warn "Homepage: Proxmox widget needs an API token — a password would expose root in a widget. Add a token to ${HOMEPAGE_ENV}."
    fi
else
    warn "Homepage config not found at ${HOMEPAGE_CONFIG} — skipping dashboard finalisation."
fi

# ─── 7b. Portainer admin + dashboard widget ──────────────────────────────────
# Best-effort by design: nothing here may abort the bootstrap. Modern Portainer
# (2.20+) refuses API admin creation without an X-Setup-Token and self-locks a
# few minutes after start, so we do NOT race it — install-portainer.sh recreates
# the container with --admin-password-file, creating the admin at boot. We then
# register the local Docker environment (id 1, which the widget references) and
# mint the Homepage widget API key.
if [[ "${#SEM_PASS}" -lt 12 ]]; then
    warn "Portainer: admin password under 12 chars — skipping Portainer setup."
elif [[ ! -f "${PORTAINER_INSTALL}" ]]; then
    warn "Portainer installer not found (${PORTAINER_INSTALL}) — skipping Portainer setup."
else
    P_URL="https://127.0.0.1:9443/api"
    pcurl() { # pcurl <out-prefix> <METHOD> <curl args...> — never fails the script
        # Method MUST go through -X. Passing it as a bare arg makes curl treat
        # it as an extra URL to fetch, which pollutes the body (jq then fails)
        # and can burn the --max-time budget — that is what stopped the local
        # Docker environment from being created on a fresh deploy.
        local _pfx="$1" _method="$2"; shift 2; local resp code
        resp=$(curl -sk --max-time 20 -X "${_method}" -w '\n%{http_code}' "$@" 2>/dev/null) || resp=$'\n000'
        code="${resp##*$'\n'}"
        printf -v "${_pfx}_CODE" '%s' "${code}"
        printf -v "${_pfx}_BODY" '%s' "${resp%$'\n'*}"
        return 0
    }
    log "Portainer: creating admin at container start (--admin-password-file)..."
    PORTAINER_ADMIN_PASSWORD="${SEM_PASS}" bash "${PORTAINER_INSTALL}" >/dev/null 2>&1 \
        || warn "Portainer installer reported an error — check: docker logs portainer"
    P_READY=0
    for _ in $(seq 1 12); do
        pcurl PS GET "${P_URL}/system/status"
        [[ "${PS_CODE}" == "200" ]] && { P_READY=1; break; }
        sleep 5
    done
    if [[ "${P_READY}" != "1" ]]; then
        warn "Portainer API not responding (last ${PS_CODE:-none}) — check https://${SERVER_IP}:9443"
    else
        # Admin creation completes a moment after boot — retry auth briefly.
        P_JWT=""
        for _ in $(seq 1 6); do
            pcurl PA POST "${P_URL}/auth" -H "Content-Type: application/json" \
                -d "$(jq -n --arg p "${SEM_PASS}" '{username:"admin",password:$p}')"
            P_JWT=$(echo "${PA_BODY}" | jq -r '.jwt // empty' 2>/dev/null) || P_JWT=""
            [[ -n "${P_JWT}" ]] && break
            sleep 5
        done
        if [[ -z "${P_JWT}" ]]; then
            warn "Portainer auth failed (HTTP ${PA_CODE}: ${PA_BODY:0:160}) — verify at https://${SERVER_IP}:9443"
        else
            # Ensure a local Docker environment exists, then point the widget at
            # its REAL id (a fresh Portainer numbers it 1, but don't assume).
            pcurl PE GET "${P_URL}/endpoints" -H "Authorization: Bearer ${P_JWT}"
            EP_ID=$(echo "${PE_BODY}" | jq -r '[.[] | select(.Type==1 or .Name=="local")][0].Id // empty' 2>/dev/null) || EP_ID=""
            if [[ -z "${EP_ID}" ]]; then
                pcurl PC POST "${P_URL}/endpoints" -H "Authorization: Bearer ${P_JWT}" \
                    -F "Name=local" -F "EndpointCreationType=1"
                EP_ID=$(echo "${PC_BODY}" | jq -r '.Id // empty' 2>/dev/null) || EP_ID=""
                [[ -n "${EP_ID}" ]] && log "Portainer: local Docker environment registered (id ${EP_ID})" \
                    || warn "Portainer: could not register local environment (HTTP ${PC_CODE}: ${PC_BODY:0:160})"
            else
                log "Portainer: local Docker environment already present (id ${EP_ID})"
            fi
            # Repoint the Homepage Portainer widget at the actual endpoint id.
            if [[ -n "${EP_ID}" && -f "${HOMEPAGE_CONFIG}/services.yaml" ]]; then
                sed -i -E "s/^([[:space:]]*)env:[[:space:]]*[0-9]+/\1env: ${EP_ID}/" "${HOMEPAGE_CONFIG}/services.yaml"
            fi
            # Mint the widget key — needs the admin's id and the password in body.
            P_AID=$(curl -sk --max-time 20 "${P_URL}/users" -H "Authorization: Bearer ${P_JWT}" 2>/dev/null \
                    | jq -r '.[] | select(.Username=="admin") | .Id' 2>/dev/null)
            P_AID="${P_AID:-1}"
            pcurl PT POST "${P_URL}/users/${P_AID}/tokens" -H "Authorization: Bearer ${P_JWT}" \
                -H "Content-Type: application/json" \
                -d "$(jq -n --arg p "${SEM_PASS}" '{password:$p, description:"homepage-widget"}')"
            P_KEY=$(echo "${PT_BODY}" | jq -r '.rawAPIKey // empty' 2>/dev/null) || P_KEY=""
            if [[ -n "${P_KEY}" ]]; then
                set_env_kv "${HOMEPAGE_ENV}" HOMEPAGE_VAR_PORTAINER_KEY "${P_KEY}"
                log "Portainer: dashboard widget key stored"
            else
                warn "Portainer: could not mint an API key (HTTP ${PT_CODE}: ${PT_BODY:0:160}) — widget errors until a key is added to ${HOMEPAGE_ENV}"
            fi
        fi
    fi
fi

# ─── 7c. Recreate the Homepage container so it loads the new credentials ──────
# docker restart would NOT re-read the --env-file; install-homepage.sh removes
# and re-runs the container, leaving the existing config and env file in place.
if [[ -f "${HOMEPAGE_INSTALL}" ]]; then
    bash "${HOMEPAGE_INSTALL}" >/dev/null 2>&1 \
        && log "Homepage recreated with live credentials (http://${SERVER_IP}:3002/)" \
        || warn "Could not recreate the homepage container — check: docker logs homepage"
else
    warn "Homepage installer not found (${HOMEPAGE_INSTALL}) — recreate homepage manually to load creds."
fi

# ─── 8. SSH password access check ────────────────────────────────────────────
# The build should have configured password SSH for the admin account via
# the common role's sshd template. Verify, and repair if missing.
if ! grep -q "^Match User" /etc/ssh/sshd_config; then
    echo ""
    warn "sshd_config has no per-user password override — SSH is key-only for everyone."
    SSH_PW_USER=""
    if [[ "${NONINTERACTIVE}" != "1" ]]; then
        read -r -p "Enable SSH password login for one admin account? Username (Enter = skip): " SSH_PW_USER
    fi
    if [[ -n "${SSH_PW_USER}" ]]; then
        if id "${SSH_PW_USER}" &>/dev/null; then
            if ! passwd -S "${SSH_PW_USER}" 2>/dev/null | awk '{exit ($2=="P")?0:1}'; then
                log "'${SSH_PW_USER}' has no usable password — set one now:"
                passwd "${SSH_PW_USER}"
            fi
            cat >> /etc/ssh/sshd_config <<SSHD_EOF

# Per-user override added by bootstrap-toolbox.sh — keep at end of file
Match User ${SSH_PW_USER}
    PasswordAuthentication yes
SSHD_EOF
            sshd -t && systemctl restart ssh && log "Password SSH enabled for '${SSH_PW_USER}' (all other accounts stay key-only)" \
                || warn "sshd config test failed — change NOT applied cleanly, inspect /etc/ssh/sshd_config"
        else
            warn "User '${SSH_PW_USER}' does not exist — skipping."
        fi
    fi
else
    log "SSH per-user password override already present."
fi

# ─── 9. Firewall lockdown ────────────────────────────────────────────────────
echo ""
log "Firewall: the build baseline allows all private-subnet traffic. You can"
log "lock this server down so that ONLY a management subnet may reach it"
log "(SSH 22, Semaphore 80, Homepage 3002, Webmin 10000, ICMP)."
warn "Run this from the Proxmox console or from a host INSIDE that subnet —"
warn "an SSH session from anywhere else will be cut off when rules apply."
if [[ -z "${MGMT_SUBNET}" && "${NONINTERACTIVE}" != "1" ]]; then
    read -r -p "Management subnet to allow, e.g. 192.168.4.0/24 (Enter = skip, keep baseline): " MGMT_SUBNET
fi
if [[ -n "${MGMT_SUBNET}" ]]; then
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
    FW_SCRIPT="${REPO_ROOT}/infrastructure/networking/firewall/setup-iptables.sh"
    [[ -f "${FW_SCRIPT}" ]] || FW_SCRIPT="/git/monorepo/infrastructure/networking/firewall/setup-iptables.sh"
    if [[ -f "${FW_SCRIPT}" ]]; then
        chmod +x "${FW_SCRIPT}"
        MGMT_SUBNETS="${MGMT_SUBNET}" ALLOWED_TCP_PORTS="22,80,3002,9443,10000" "${FW_SCRIPT}"             && log "Firewall locked down to ${MGMT_SUBNET}"             || warn "Firewall script reported an error — check its log; baseline rules may still apply."
    else
        warn "setup-iptables.sh not found in the repo checkout — firewall unchanged."
    fi
else
    log "Firewall unchanged (baseline rules still in effect)."
fi

# ─── 10. Golden image templates ──────────────────────────────────────────────
# A toolbox without templates can't deploy anything yet. Offer to build the
# golden images now — each runs as a Semaphore task on this server (watch in the
# UI). Non-interactive runs opt in via AUTO_BUILD_GOLDEN=1.
#   • Ubuntu 24.04 and 26.04 stage their own ISOs (fetch-ubuntu-iso.sh), so they
#     always build.
#   • Windows 2025 needs its ISO pre-uploaded (Microsoft licensing = no auto-
#     download). We only auto-start it when the ISO named by win_iso_file in
#     homelab.pkrvars.hcl actually exists on Proxmox storage; otherwise we skip
#     and point at the manual build.
IP_ADDR=$(hostname -I | awk '{print $1}')
SITE_FILE="${REPO_ROOT}/automation/packer/environments/homelab.pkrvars.hcl"
[[ -f "${SITE_FILE}" ]] || SITE_FILE="/git/monorepo/automation/packer/environments/homelab.pkrvars.hcl"
BUILD_GOLDEN="${AUTO_BUILD_GOLDEN:-}"
if [[ -z "${BUILD_GOLDEN}" && "${NONINTERACTIVE}" != "1" ]]; then
    read -r -p "Start building the golden image templates now (Ubuntu 24.04 + 26.04, and Windows if its ISO is present)? (Y/n): " ans
    [[ "${ans}" =~ ^[Nn] ]] || BUILD_GOLDEN=1
fi

start_golden() { # start_golden <template-id> <label> <manual-name>
    local tid="$1" label="$2" name="$3" task
    [[ -n "${tid}" ]] || { warn "${label}: job template not found — skipping."; return; }
    task=$(api POST "${P}/tasks" "$(jq -n --argjson t "${tid}" '{template_id: $t}')" | jq -r '.id // empty')
    [[ -n "${task}" ]] \
        && log "${label} build started (Semaphore task ${task}) — watch: http://${IP_ADDR}/ -> Tasks" \
        || warn "Could not start ${label} — run it manually: Semaphore -> ${name}"
}

# Is a Proxmox ISO volid actually on storage? 0 = present, 1 = absent,
# 2 = cannot tell (no API token). Token auth mirrors the rest of the toolbox.
proxmox_iso_present() { # proxmox_iso_present <volid>
    local volid="$1" storage node hdr
    [[ -n "${volid}" && -n "${PVE_TOKEN_ID}" && -n "${PVE_TOKEN_SECRET}" ]] || return 2
    hdr="Authorization: PVEAPIToken=${PVE_USER}!${PVE_TOKEN_ID}=${PVE_TOKEN_SECRET}"
    storage="${volid%%:*}"
    node="${PVE_NODE}"
    [[ -n "${node}" ]] || node=$(curl -sk --max-time 15 -H "${hdr}" "https://${PVE_HOST}:8006/api2/json/nodes" 2>/dev/null | jq -r '.data[0].node // empty')
    [[ -n "${node}" ]] || return 2
    curl -sk --max-time 20 -H "${hdr}" "https://${PVE_HOST}:8006/api2/json/nodes/${node}/storage/${storage}/content?content=iso" 2>/dev/null \
        | jq -e --arg v "${volid}" '.data[]? | select(.volid == $v)' >/dev/null 2>&1
}

# Add/update a plaintext KEY=VALUE in a Semaphore environment group without
# touching its encrypted secrets (secrets are separate rows; PUTting env/json
# leaves them intact). Returns non-zero if the API call fails.
set_semaphore_env_var() { # set_semaphore_env_var <env_id> <key> <value>
    local eid="$1" key="$2" val="$3" cur envstr body
    cur=$(api GET "${P}/environment/${eid}" 2>/dev/null) || return 1
    envstr=$(echo "${cur}" | jq -r '.env // "{}"' | jq -c --arg k "${key}" --arg v "${val}" '. + {($k):$v}' 2>/dev/null) || return 1
    body=$(echo "${cur}" | jq -c --arg e "${envstr}" '{id, name, project_id, json: (.json // "{}"), env: $e}' 2>/dev/null) || return 1
    api PUT "${P}/environment/${eid}" "${body}" >/dev/null 2>&1
}

if [[ "${BUILD_GOLDEN}" == "1" ]]; then
    start_golden "${GOLD_TPL_ID:-}"   "Ubuntu 24.04 golden image" "Build Golden Image — Ubuntu 24.04"
    sleep 20   # stagger: avoid concurrent 'packer init' plugin-download races
    start_golden "${GOLD26_TPL_ID:-}" "Ubuntu 26.04 golden image" "Build Golden Image — Ubuntu 26.04"
    sleep 20

    WIN_ISO_VOLID="$(grep -E '^\s*win_iso_file\s*=' "${SITE_FILE}" 2>/dev/null | head -1 | sed -E 's/^[^=]*=\s*"?([^"#]*[^"# ])"?.*$/\1/')"
    if proxmox_iso_present "${WIN_ISO_VOLID}"; then
        log "Windows ISO present on Proxmox (${WIN_ISO_VOLID}) — starting the Windows build."
        start_golden "${GOLDWIN_TPL_ID:-}" "Windows Server 2025 golden image" "Build Golden Image — Windows 2025"
    else
        WRC=$?
        if [[ "${NONINTERACTIVE}" == "1" ]]; then
            case "${WRC}" in
                2) warn "Windows auto-build skipped — a Proxmox API token is needed to verify the ISO. Upload the ISO, then run 'Build Golden Image — Windows 2025' in Semaphore." ;;
                *) log  "Windows auto-build skipped — ISO '${WIN_ISO_VOLID:-unset}' not found on Proxmox storage. Upload it (see win2025-proxmox/README.md), then run 'Build Golden Image — Windows 2025' in Semaphore." ;;
            esac
        else
            warn "Windows Server 2025 ISO '${WIN_ISO_VOLID:-unset}' was not found on Proxmox storage."
            read -r -p "Enter the ISO volid to use (format storage:iso/name.iso), or press Enter to skip the Windows build: " USER_VOLID
            if [[ -z "${USER_VOLID}" ]]; then
                log "Windows golden image skipped — upload the ISO later and run 'Build Golden Image — Windows 2025'."
            else
                if proxmox_iso_present "${USER_VOLID}"; then VRC=0; else VRC=$?; fi
                if [[ "${VRC}" == "0" || "${VRC}" == "2" ]]; then
                    [[ "${VRC}" == "2" ]] && warn "Could not verify '${USER_VOLID}' (no API token) — trusting your input."
                    if set_semaphore_env_var "${ENV_ID}" PKR_VAR_win_iso_file "${USER_VOLID}"; then
                        log "Windows ISO set to ${USER_VOLID} (saved to the Proxmox variable group) — starting the build."
                        start_golden "${GOLDWIN_TPL_ID:-}" "Windows Server 2025 golden image" "Build Golden Image — Windows 2025"
                    else
                        warn "Verified the ISO but could not save it to Semaphore — set PKR_VAR_win_iso_file=${USER_VOLID} in the Proxmox variable group, then run 'Build Golden Image — Windows 2025'."
                    fi
                else
                    warn "'${USER_VOLID}' was not found on Proxmox storage either — skipping. Upload the ISO, then run 'Build Golden Image — Windows 2025'."
                fi
            fi
        fi
    fi
fi

mkdir -p /opt/toolbox && touch /opt/toolbox/.bootstrapped
IP=$(hostname -I | awk '{print $1}')
echo ""
log "Bootstrap complete."
log "  Semaphore     : http://${IP}/  (login: admin)"
log "  Project       : ${PROJECT_NAME}"
log "  Job templates : Provision VM, Deploy Ubuntu 24/26, Deploy Windows 2025, Apply Baseline (Linux), Deploy Vault, ITA Linux Customisations, IPTables, Fail2Ban, Webmin, Build Golden Image (x3)"
log "  Inventories   : per-OS Hosts + Linux Baseline (default-build group)"
log "  Portainer     : https://${SERVER_IP}:9443/  (admin)"
log ""
log "To provision your first VM:"
log "  1. Open http://${IP}/ and log in"
log "  2. Task Templates → 'Provision VM (Proxmox)' → Run"
log "  3. Fill in the survey (VM name + template to clone) and watch the task log"
log ""
log "To stand up the Vault server: provision a VM, note its IP, then run"
log "'Deploy Vault Server' — and store the unseal keys it prints somewhere safe."
