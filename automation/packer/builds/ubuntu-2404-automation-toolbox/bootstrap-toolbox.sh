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
#   sudo /git/monorepo/automation/packer/builds/ubuntu-2404-automation-toolbox/bootstrap-toolbox.sh
#
# You will be prompted for:
#   1. The Semaphore admin password (set at image build time)
#   2. Proxmox API host (default: 192.168.4.150)
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
# Version:           1.0
# Date:              02-07-2026
# =============================================================================

set -euo pipefail

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
read -r -s -p "Semaphore admin password: " SEM_PASS; echo
read -r -p "Proxmox API host [192.168.4.150]: " PVE_HOST
PVE_HOST="${PVE_HOST:-192.168.4.150}"
read -r -p "Proxmox API user [root@pam]: " PVE_USER
PVE_USER="${PVE_USER:-root@pam}"
read -r -p "Proxmox API token ID (leave empty to use password auth): " PVE_TOKEN_ID
if [[ -n "${PVE_TOKEN_ID}" ]]; then
    read -r -s -p "Proxmox API token secret: " PVE_TOKEN_SECRET; echo
    PVE_PASSWORD=""
else
    read -r -s -p "Proxmox password for ${PVE_USER}: " PVE_PASSWORD; echo
    PVE_TOKEN_SECRET=""
    warn "Password auth works, but an API token is the better long-term choice — see the header of this script."
fi
read -r -p "Proxmox node name [POSVMPWS01]: " PVE_NODE
PVE_NODE="${PVE_NODE:-POSVMPWS01}"

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

# ─── 3. Variable Group (Proxmox connection) ──────────────────────────────────
ENV_ID=$(api GET "${P}/environment" | find_id "Proxmox")
if [[ -z "${ENV_ID}" ]]; then
    ENV_BODY=$(jq -n \
        --argjson pid "${PROJECT_ID}" \
        --arg host "${PVE_HOST}" --arg user "${PVE_USER}" --arg node "${PVE_NODE}" \
        --arg tid "${PVE_TOKEN_ID}" --arg tsec "${PVE_TOKEN_SECRET}" --arg pw "${PVE_PASSWORD}" \
        '{
          name: "Proxmox", project_id: $pid, json: "{}",
          env: ({PROXMOX_HOST: $host, PROXMOX_USER: $user, PROXMOX_NODE: $node, PROXMOX_TOKEN_ID: $tid} | tojson),
          secrets: ([
            (if $tsec != "" then {type: "env", name: "PROXMOX_TOKEN_SECRET", secret: $tsec, operation: "create"} else empty end),
            (if $pw   != "" then {type: "env", name: "PROXMOX_PASSWORD",     secret: $pw,   operation: "create"} else empty end)
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
        "$(jq -n --argjson pid "${PROJECT_ID}" --argjson kid "${NONE_KEY_ID}" \
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
            {name: "vm_name",      title: "VM name",                        type: "",    required: true},
            {name: "vm_template",  title: "Proxmox template to clone",      type: "",    required: true},
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

# ─── Summary ─────────────────────────────────────────────────────────────────
# ─── 7. Firewall lockdown ────────────────────────────────────────────────────
echo ""
log "Firewall: the build baseline allows all private-subnet traffic. You can"
log "lock this server down so that ONLY a management subnet may reach it"
log "(SSH 22, Semaphore 80, Homepage 3002, Webmin 10000, ICMP)."
warn "Run this from the Proxmox console or from a host INSIDE that subnet —"
warn "an SSH session from anywhere else will be cut off when rules apply."
read -r -p "Management subnet to allow, e.g. 192.168.4.0/24 (Enter = skip, keep baseline): " MGMT_SUBNET
if [[ -n "${MGMT_SUBNET}" ]]; then
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
    FW_SCRIPT="${REPO_ROOT}/infrastructure/networking/firewall/setup-iptables.sh"
    [[ -f "${FW_SCRIPT}" ]] || FW_SCRIPT="/git/monorepo/infrastructure/networking/firewall/setup-iptables.sh"
    if [[ -f "${FW_SCRIPT}" ]]; then
        chmod +x "${FW_SCRIPT}"
        MGMT_SUBNETS="${MGMT_SUBNET}" ALLOWED_TCP_PORTS="22,80,3002,10000" "${FW_SCRIPT}"             && log "Firewall locked down to ${MGMT_SUBNET}"             || warn "Firewall script reported an error — check its log; baseline rules may still apply."
    else
        warn "setup-iptables.sh not found in the repo checkout — firewall unchanged."
    fi
else
    log "Firewall unchanged (baseline rules still in effect)."
fi

mkdir -p /opt/toolbox && touch /opt/toolbox/.bootstrapped
IP=$(hostname -I | awk '{print $1}')
echo ""
log "Bootstrap complete."
log "  Semaphore     : http://${IP}/  (login: admin)"
log "  Project       : ${PROJECT_NAME}"
log "  Job templates : 'Provision VM (Proxmox)', 'Deploy Vault Server'"
log ""
log "To provision your first VM:"
log "  1. Open http://${IP}/ and log in"
log "  2. Task Templates → 'Provision VM (Proxmox)' → Run"
log "  3. Fill in the survey (VM name + template to clone) and watch the task log"
log ""
log "To stand up the Vault server: provision a VM, note its IP, then run"
log "'Deploy Vault Server' — and store the unseal keys it prints somewhere safe."
