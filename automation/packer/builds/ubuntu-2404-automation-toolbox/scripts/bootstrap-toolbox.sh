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
        '{
          name: "Proxmox", project_id: $pid, json: "{}",
          env: ({PROXMOX_HOST: $host, PROXMOX_USER: $user, PROXMOX_NODE: $node, PROXMOX_TOKEN_ID: $tid, PROVISION_SSH_PUBKEY: $pub} | tojson),
          secrets: ([
            (if $tsec  != "" then {type: "env", name: "PROXMOX_TOKEN_SECRET", secret: $tsec,  operation: "create"} else empty end),
            (if $pw    != "" then {type: "env", name: "PROXMOX_PASSWORD",     secret: $pw,    operation: "create"} else empty end),
            (if $winrm != "" then {type: "env", name: "WINRM_PASSWORD",       secret: $winrm, operation: "create"} else empty end)
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

# ─── 6. Job Templates ────────────────────────────────────────────────────────
TPL_JSON=$(api GET "${P}/templates")

PROV_TPL_ID=$(echo "${TPL_JSON}" | find_id "Provision VM (Proxmox)")
if [[ -z "${PROV_TPL_ID}" ]]; then
    PROV_TPL_ID=$(api POST "${P}/templates" "$(jq -n \
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
    log "Job template 'Provision VM (Proxmox)' created (id ${PROV_TPL_ID})"
else
    log "Job template 'Provision VM (Proxmox)' already exists (id ${PROV_TPL_ID})"
fi

VAULT_TPL_ID=$(echo "${TPL_JSON}" | find_id "Deploy Vault Server")
if [[ -z "${VAULT_TPL_ID}" ]]; then
    VAULT_TPL_ID=$(api POST "${P}/templates" "$(jq -n \
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
    GOLD_TPL_ID=$(api POST "${P}/templates" "$(jq -n \
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
    G_ID=$(echo "${TPL_JSON}" | find_id "${G_NAME}")
    if [[ -z "${G_ID}" ]]; then
        G_ID=$(api POST "${P}/templates" "$(jq -n \
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
done

SEED_TPL() { # SEED_TPL <name> <playbook> <description> <survey-json>
    local T_ID
    T_ID=$(echo "${TPL_JSON}" | find_id "$1")
    if [[ -z "${T_ID}" ]]; then
        T_ID=$(api POST "${P}/templates" "$(jq -n \
            --argjson pid "${PROJECT_ID}" --argjson inv "${LOCAL_INV_ID}" \
            --argjson rid "${REPO_ID}" --argjson eid "${ENV_ID}" \
            --arg name "$1" --arg play "$2" --arg desc "$3" --argjson survey "$4" \
            '{project_id: $pid, name: $name, app: "ansible", playbook: $play,
              inventory_id: $inv, repository_id: $rid, environment_id: $eid,
              arguments: "[]", type: "", description: $desc, survey_vars: $survey}')" | jq -r '.id')
        log "Job template '$1' created (id ${T_ID})"
    else
        log "Job template '$1' already exists (id ${T_ID})"
    fi
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

WEBMIN_TPL_ID=$(echo "${TPL_JSON}" | find_id "Deploy Webmin")
if [[ -z "${WEBMIN_TPL_ID}" ]]; then
    WEBMIN_TPL_ID=$(api POST "${P}/templates" "$(jq -n \
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
    log "Job template 'Deploy Webmin' created (id ${WEBMIN_TPL_ID})"
else
    log "Job template 'Deploy Webmin' already exists (id ${WEBMIN_TPL_ID})"
fi

PROBE_TPL_ID=$(echo "${TPL_JSON}" | find_id "Diagnostics — Task Probe")
if [[ -z "${PROBE_TPL_ID}" ]]; then
    PROBE_TPL_ID=$(api POST "${P}/templates" "$(jq -n \
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

# ─── Summary ─────────────────────────────────────────────────────────────────
# ─── 7. Finalise the Homepage dashboard ──────────────────────────────────────
HOMEPAGE_CONFIG="/opt/homepage/config"
HOMEPAGE_ENV="/opt/homepage/.env.homepage"
SERVER_IP=$(hostname -I | awk '{print $1}')
if [[ -d "${HOMEPAGE_CONFIG}" ]]; then
    if grep -q "toolbox.lab.local" "${HOMEPAGE_CONFIG}/services.yaml" 2>/dev/null; then
        sed -i "s/toolbox\.lab\.local/${SERVER_IP}/g" "${HOMEPAGE_CONFIG}/services.yaml"
        log "Homepage: placeholder hostnames replaced with ${SERVER_IP}"
    fi
    if grep -q "PROXMOX-HOST-PLACEHOLDER" "${HOMEPAGE_CONFIG}/services.yaml" 2>/dev/null; then
        sed -i "s/PROXMOX-HOST-PLACEHOLDER/${PVE_HOST}/g" "${HOMEPAGE_CONFIG}/services.yaml"
        log "Homepage: Proxmox tile pointed at ${PVE_HOST}"
    fi
    if [[ -n "${PVE_TOKEN_ID}" && -f "${HOMEPAGE_ENV}" ]]; then
        # Homepage's Proxmox widget authenticates with an API token:
        # username = user@realm!tokenid, password = token secret.
        cat > "${HOMEPAGE_ENV}" <<HP_EOF
# Homepage widget credentials — written by bootstrap-toolbox.sh. Never commit.
HOMEPAGE_VAR_PROXMOX_USER=${PVE_USER}!${PVE_TOKEN_ID}
HOMEPAGE_VAR_PROXMOX_PASS=${PVE_TOKEN_SECRET}
HOMEPAGE_VAR_PROXMOX_NODE=${PVE_NODE}
HP_EOF
        chmod 600 "${HOMEPAGE_ENV}"
        log "Homepage: Proxmox widget credentials written (token auth)"
    elif [[ -z "${PVE_TOKEN_ID}" ]]; then
        warn "Homepage: Proxmox widget needs an API token — using password auth here would put the root password in a widget. Edit ${HOMEPAGE_ENV} once you create a token."
    fi
    docker restart homepage >/dev/null 2>&1 && log "Homepage restarted (http://${SERVER_IP}:3002/)" \
        || warn "Could not restart the homepage container — is Docker running?"
else
    warn "Homepage config not found at ${HOMEPAGE_CONFIG} — skipping dashboard finalisation."
fi

# ─── 7b. Portainer initialisation ────────────────────────────────────────────
# Best-effort by design: NOTHING in this section may abort the bootstrap.
# Portainer locks its init endpoint ~5 min after container start; a restart
# re-opens it. Every call logs its HTTP status so failures are diagnosable.
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx portainer; then
    P_URL="https://127.0.0.1:9443/api"
    P_PASS="${SEM_PASS}"
    pcurl() { # pcurl <out-var-prefix> <curl args...> — never fails the script
        local _pfx="$1"; shift
        local resp code
        resp=$(curl -sk --max-time 15 -w '\n%{http_code}' "$@" 2>/dev/null) || resp=$'\n000'
        code="${resp##*$'\n'}"
        printf -v "${_pfx}_CODE" '%s' "${code}"
        printf -v "${_pfx}_BODY" '%s' "${resp%$'\n'*}"
        return 0
    }
    if [[ "${#P_PASS}" -lt 12 ]]; then
        warn "Portainer needs a 12+ character admin password — set it manually at https://${SERVER_IP}:9443"
    else
        # Restart Portainer FIRST: its admin-init endpoint locks ~5 min after
        # container start, and the bootstrap can arrive later than that. A
        # restart opens a fresh window deterministically instead of racing it.
        docker restart portainer >/dev/null 2>&1 || true
        # wait for the API to answer (container restarting)
        P_READY=0
        for _ in 1 2 3 4 5 6; do
            pcurl PS GET "${P_URL}/system/status"
            [[ "${PS_CODE}" == "200" ]] && { P_READY=1; break; }
            sleep 5
        done
        if [[ "${P_READY}" != "1" ]]; then
            warn "Portainer API not responding (last status ${PS_CODE:-none}) — initialise it manually at https://${SERVER_IP}:9443"
        else
            pcurl PI POST "${P_URL}/users/admin/init"                 -H "Content-Type: application/json"                 -d "$(jq -n --arg p "${P_PASS}" '{Username: "admin", Password: $p}')"
            case "${PI_CODE}" in
                200) log "Portainer admin initialised (admin / same password as Semaphore)" ;;
                409) log "Portainer admin already initialised — continuing" ;;
                408) warn "Portainer init window expired — restarting the container re-opens it: docker restart portainer, then initialise at https://${SERVER_IP}:9443"
                     docker restart portainer >/dev/null 2>&1 || true
                     sleep 5
                     pcurl PI POST "${P_URL}/users/admin/init" -H "Content-Type: application/json"                          -d "$(jq -n --arg p "${P_PASS}" '{Username: "admin", Password: $p}')"
                     [[ "${PI_CODE}" == "200" ]] && log "Portainer admin initialised after restart"                          || warn "Init still failing (HTTP ${PI_CODE}): ${PI_BODY:0:200}" ;;
                *)   warn "Portainer init returned HTTP ${PI_CODE}: ${PI_BODY:0:200}" ;;
            esac
            pcurl PA POST "${P_URL}/auth" -H "Content-Type: application/json"                 -d "$(jq -n --arg p "${P_PASS}" '{username: "admin", password: $p}')"
            P_JWT=$(echo "${PA_BODY}" | jq -r '.jwt // empty' 2>/dev/null) || P_JWT=""
            if [[ -n "${P_JWT}" ]]; then
                pcurl PT POST "${P_URL}/users/1/tokens"                     -H "Authorization: Bearer ${P_JWT}" -H "Content-Type: application/json"                     -d '{"description":"homepage-widget"}'
                P_KEY=$(echo "${PT_BODY}" | jq -r '.rawAPIKey // empty' 2>/dev/null) || P_KEY=""
                if [[ -n "${P_KEY}" && -f "${HOMEPAGE_ENV}" ]]; then
                    sed -i "s|^HOMEPAGE_VAR_PORTAINER_KEY=.*|HOMEPAGE_VAR_PORTAINER_KEY=${P_KEY}|" "${HOMEPAGE_ENV}" || true
                    docker restart homepage >/dev/null 2>&1 || true
                    log "Portainer dashboard widget wired (API key stored for Homepage)"
                else
                    warn "Could not mint a Portainer API key (HTTP ${PT_CODE}: ${PT_BODY:0:200}) — widget shows an error until a key is added to ${HOMEPAGE_ENV}"
                fi
            else
                warn "Portainer authentication failed (HTTP ${PA_CODE}: ${PA_BODY:0:200}) — initialise/verify at https://${SERVER_IP}:9443"
            fi
        fi
    fi
else
    warn "Portainer container not running — skipping its initialisation."
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
# A toolbox without templates can't deploy anything yet — offer to start the
# Ubuntu 24.04 golden image build right away (runs as a Semaphore task on
# this server, ~20-30 min, watch it in the UI). Non-interactive runs opt in
# via AUTO_BUILD_GOLDEN=1. Windows 2025 / Ubuntu 26.04 join this list once
# their builds get the same standalone treatment.
BUILD_GOLDEN="${AUTO_BUILD_GOLDEN:-}"
if [[ -z "${BUILD_GOLDEN}" && "${NONINTERACTIVE}" != "1" ]]; then
    read -r -p "Start building the Ubuntu 24.04 golden image template now? (Y/n): " ans
    [[ "${ans}" =~ ^[Nn] ]] || BUILD_GOLDEN=1
fi
if [[ "${BUILD_GOLDEN}" == "1" && -n "${GOLD_TPL_ID:-}" ]]; then
    TASK_ID=$(api POST "${P}/tasks"         "$(jq -n --argjson tid "${GOLD_TPL_ID}" '{template_id: $tid}')" | jq -r '.id // empty')
    if [[ -n "${TASK_ID}" ]]; then
        log "Golden image build started (Semaphore task ${TASK_ID}) — progress: http://$(hostname -I | awk '{print $1}')/ → Tasks"
        log "The template 'ubuntu-2404-golden-<timestamp>' appears in Proxmox when it finishes (~20-30 min)."
    else
        warn "Could not start the golden image task — run it manually: Semaphore → Build Golden Image — Ubuntu 24.04"
    fi
elif [[ "${BUILD_GOLDEN}" == "1" ]]; then
    warn "Golden image job template not found — skipping auto-build."
fi

mkdir -p /opt/toolbox && touch /opt/toolbox/.bootstrapped
IP=$(hostname -I | awk '{print $1}')
echo ""
log "Bootstrap complete."
log "  Semaphore     : http://${IP}/  (login: admin)"
log "  Project       : ${PROJECT_NAME}"
log "  Job templates : Provision VM, Deploy Vault, ITA Linux Customisations, IPTables, Fail2Ban, Webmin, Build Golden Image (x3)"
log "  Portainer     : https://${SERVER_IP}:9443/  (admin)"
log ""
log "To provision your first VM:"
log "  1. Open http://${IP}/ and log in"
log "  2. Task Templates → 'Provision VM (Proxmox)' → Run"
log "  3. Fill in the survey (VM name + template to clone) and watch the task log"
log ""
log "To stand up the Vault server: provision a VM, note its IP, then run"
log "'Deploy Vault Server' — and store the unseal keys it prints somewhere safe."
