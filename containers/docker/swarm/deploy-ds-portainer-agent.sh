#!/usr/bin/env bash
# =============================================================================
# Deploy the Portainer Agent across a Docker Swarm cluster
# =============================================================================
# Run on a Swarm MANAGER. Discovers the cluster's nodes from the Swarm itself,
# prepares each node over SSH (iptables rules for Swarm + agent ports, the
# shared data directory), then deploys the agent as a global service.
#
# Access to the nodes is SSH key + passwordless sudo, nothing else:
#   - The repo's server baseline disables SSH password login, so a password
#     path could not work on hosts built from it — and the old one put the
#     password on every remote command line (visible in process lists and
#     shell history on every node).
#   - Host keys are accepted on first contact and pinned after that
#     (StrictHostKeyChecking=accept-new), the same policy the Ansible
#     playbooks use.
#
# Environment / options:
#   SSH_USER        SSH user on the nodes (default: current user)
#   STORAGE_PATH    Agent data directory on every node
#                   (default: /mnt/nfs/docker/portainer; prompted if a TTY)
#   NODES           Space-separated node list to use INSTEAD of Swarm discovery
#
# Prerequisites: Docker Swarm initialised, this node a manager, SSH key access
# to every node with 'sudo -n' working there.
# Logs to /logs/deploy-portainer-agent-YYYYMMDD.log, or ~/logs if /logs is
# not writable. Deploys the agent only — assumes an existing Portainer Server.
# =============================================================================

set -euo pipefail

# ─── Logging ─────────────────────────────────────────────────────────────────
LOG_DIR="/logs"
LOG_FILE="${LOG_DIR}/deploy-portainer-agent-$(date '+%Y%m%d').log"
if ! { mkdir -p "${LOG_DIR}" && touch "${LOG_FILE}"; } 2>/dev/null; then
    LOG_DIR="${HOME}/logs"
    LOG_FILE="${LOG_DIR}/deploy-portainer-agent-$(date '+%Y%m%d').log"
    mkdir -p "${LOG_DIR}" && touch "${LOG_FILE}" || { echo "Cannot create ${LOG_FILE}" >&2; exit 1; }
    echo "Cannot write to /logs — logging to ${LOG_FILE}" >&2
fi
log()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO]  $*" | tee -a "${LOG_FILE}"; }
warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN]  $*" | tee -a "${LOG_FILE}"; }
fail() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "${LOG_FILE}" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

SSH_USER="${SSH_USER:-${USER}}"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o BatchMode=yes -o ConnectTimeout=10)
# Run a command on a node as root (key auth + passwordless sudo, no secrets).
# The command travels on stdin to a root bash, so the WHOLE pipeline runs as
# root and no quoting of the remote command line is needed.
remote() { # remote <node> <command...>
    local node="$1"; shift
    ssh "${SSH_OPTS[@]}" "${SSH_USER}@${node}" 'sudo -n bash -s' <<< "$*"
}

log "Script started"

# ─── Local pre-flight ────────────────────────────────────────────────────────
command -v docker &>/dev/null || fail "Docker is not installed."
docker info &>/dev/null      || fail "Cannot access the Docker daemon (join the 'docker' group or run with sudo)."
SWARM_STATE="$(docker info --format '{{.Swarm.LocalNodeState}}')"
[[ "${SWARM_STATE}" == "active" ]] || fail "This node is not part of an active Swarm (state: ${SWARM_STATE})."
docker node ls &>/dev/null   || fail "This node is not a Swarm manager — run the script on a manager."

# ─── Nodes: from the Swarm unless overridden ─────────────────────────────────
if [[ -n "${NODES:-}" ]]; then
    read -r -a NODE_LIST <<< "${NODES}"
    log "Using node list from NODES: ${NODE_LIST[*]}"
else
    mapfile -t NODE_LIST < <(docker node ls --format '{{.Hostname}}')
    log "Swarm nodes discovered: ${NODE_LIST[*]}"
fi
[[ ${#NODE_LIST[@]} -gt 0 ]] || fail "No nodes found."
log "Swarm node status:"
docker node ls | tee -a "${LOG_FILE}"

# ─── Verify key-based SSH + passwordless sudo on every node ──────────────────
for node in "${NODE_LIST[@]}"; do
    if remote "${node}" whoami > "${TMP}/ssh-${node}.out" 2>&1; then
        log "SSH key + sudo -n verified on ${node} (as ${SSH_USER})"
    else
        cat "${TMP}/ssh-${node}.out" | tee -a "${LOG_FILE}"
        fail "Cannot reach ${node} as ${SSH_USER} with an SSH key and passwordless sudo. Distribute your key (automation/ansible/playbooks/distribute-ssh-key.yml) and grant NOPASSWD sudo."
    fi
done

# ─── Storage path ────────────────────────────────────────────────────────────
STORAGE_PATH="${STORAGE_PATH:-}"
if [[ -z "${STORAGE_PATH}" && -t 0 ]]; then
    read -r -p "Storage path for Portainer Agent data [/mnt/nfs/docker/portainer]: " STORAGE_PATH
fi
STORAGE_PATH="${STORAGE_PATH:-/mnt/nfs/docker/portainer}"
log "Using storage path: ${STORAGE_PATH}"

# ─── Per-node preparation ────────────────────────────────────────────────────
REQUIRED_PORTS=("2377/tcp" "7946/tcp" "7946/udp" "4789/udp" "9001/tcp")
for node in "${NODE_LIST[@]}"; do
    log "── ${node} ──"

    # iptables-persistent layout (rules.v4 must exist for iptables-save below)
    remote "${node}" "mkdir -p /etc/iptables && touch /etc/iptables/rules.v4 && chown root:root /etc/iptables /etc/iptables/rules.v4 && chmod 755 /etc/iptables && chmod 644 /etc/iptables/rules.v4" \
        || fail "Could not prepare /etc/iptables on ${node}."

    # Swarm + agent ports in the DOCKER-SWARM chain
    if ! remote "${node}" "iptables -L DOCKER-SWARM -v -n" > "${TMP}/iptables-${node}.out" 2>&1; then
        cat "${TMP}/iptables-${node}.out" | tee -a "${LOG_FILE}"
        fail "Could not list the DOCKER-SWARM chain on ${node}."
    fi
    for port in "${REQUIRED_PORTS[@]}"; do
        port_num="${port%/*}"; proto="${port#*/}"
        if ! grep -q "${proto}.*dpt:${port_num}\b" "${TMP}/iptables-${node}.out"; then
            log "Adding iptables rule ${port} on ${node}"
            remote "${node}" "iptables -A DOCKER-SWARM -p ${proto} --dport ${port_num} -j ACCEPT && iptables-save > /etc/iptables/rules.v4" \
                || fail "Could not add the ${port} rule on ${node}."
        fi
    done

    # Agent data directory: root-owned, not world-writable. The agent runs as
    # root inside its container, so it needs nothing wider than this.
    remote "${node}" "mkdir -p '${STORAGE_PATH}' && chown root:root '${STORAGE_PATH}' && chmod 750 '${STORAGE_PATH}'" \
        || fail "Could not create ${STORAGE_PATH} on ${node}."
    if remote "${node}" "findmnt -T '${STORAGE_PATH}' -o SOURCE,FSTYPE -n" > "${TMP}/mnt-${node}.out" 2>/dev/null; then
        log "${STORAGE_PATH} on ${node}: $(tr -s ' ' < "${TMP}/mnt-${node}.out")"
    fi
done

# ─── Existing service / image ────────────────────────────────────────────────
if docker service ls --filter name=portainer_agent -q | grep -q .; then
    warn "An existing portainer_agent service was found:"
    docker service ps portainer_agent --no-trunc | tee -a "${LOG_FILE}"
    if [[ -t 0 ]]; then
        read -r -p "Remove it and redeploy? (y/N): " ans
        [[ "${ans}" =~ ^[Yy]$ ]] || fail "Leaving the existing service in place."
    fi
    docker service rm portainer_agent > "${TMP}/rm.out" 2>&1 || { cat "${TMP}/rm.out" | tee -a "${LOG_FILE}"; fail "Could not remove portainer_agent."; }
    log "Existing portainer_agent service removed."
fi

# ─── Overlay network ─────────────────────────────────────────────────────────
if docker network ls --filter name='^portainer_agent_network$' -q | grep -q .; then
    log "Overlay network portainer_agent_network already exists."
else
    docker network create --driver overlay --attachable portainer_agent_network > "${TMP}/net.out" 2>&1 \
        || { cat "${TMP}/net.out" | tee -a "${LOG_FILE}"; fail "Could not create the overlay network."; }
    log "Overlay network portainer_agent_network created."
fi

# ─── Deploy (global service, with retries) ───────────────────────────────────
RETRIES=3
for (( attempt=1; attempt<=RETRIES; attempt++ )); do
    log "Deploying Portainer Agent (attempt ${attempt}/${RETRIES})"
    if timeout 120 docker service create \
        --name portainer_agent \
        --network portainer_agent_network \
        --mode global \
        --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock \
        --mount type=bind,src="${STORAGE_PATH}",dst=/data \
        --publish mode=host,target=9001,published=9001 \
        portainer/agent:latest > "${TMP}/create.out" 2>&1; then
        log "Portainer Agent service created."
        break
    fi
    cat "${TMP}/create.out" | tee -a "${LOG_FILE}"
    if (( attempt == RETRIES )); then
        docker service ps portainer_agent --no-trunc 2>&1 | tee -a "${LOG_FILE}" || true
        fail "Failed to deploy the Portainer Agent after ${RETRIES} attempts."
    fi
    sleep 10
done

# ─── Verify ──────────────────────────────────────────────────────────────────
log "Waiting for the service to settle..."
sleep 10
docker service ls --filter name=portainer_agent | tee -a "${LOG_FILE}"
docker service ps portainer_agent --no-trunc | tee -a "${LOG_FILE}"

MANAGER="$(docker node ls --filter role=manager --format '{{.Hostname}}' | head -n 1)"
log "Portainer Agent deployment completed."
log "Connect your Portainer Server to the agent at ${MANAGER}:9001 (Swarm environment)."
log "Script completed"
