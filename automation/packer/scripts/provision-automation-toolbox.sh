#!/usr/bin/env bash
# =============================================================================
# provision-automation-toolbox.sh
#
# PURPOSE
#   Installs a comprehensive set of automation and infrastructure tools on an
#   Ubuntu management host. Run by Packer after provision.sh has already
#   hardened the base OS.
#
# TOOLS INSTALLED
#   • Ansible          — configuration management
#   • Packer           — VM / cloud image building
#   • Terraform        — infrastructure as code
#   • AWS CLI v2       — Amazon Web Services
#   • Azure CLI        — Microsoft Azure
#   • Google Cloud CLI — Google Cloud Platform
#   • kubectl          — Kubernetes management
#   • Helm             — Kubernetes package manager
#   • GitHub CLI       — Git / PR / release management
#   • Docker CE        — containers (docker-ce, buildx, compose plugin)
#   • jq / yq          — JSON and YAML processing
#   • git / curl / unzip / gnupg — common utilities
#
# USAGE
#   Called by Packer automatically. To run manually:
#     sudo bash provision-automation-toolbox.sh
# =============================================================================

set -euo pipefail

TOOLBOX_USER="toolbox"
TOOLBOX_HOME="/opt/toolbox"

log() { echo ""; echo "══════════════════════════════════════════════"; echo " $*"; echo "══════════════════════════════════════════════"; }
ok()  { echo "  ✓ $*"; }

log "Automation Toolbox Provisioner — $(date)"

# ─── 1. System prerequisites ──────────────────────────────────────────────────
log "[1/14] System prerequisites"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    git \
    jq \
    unzip \
    wget \
    python3 \
    python3-pip \
    python3-venv \
    python3-boto3 \
    python3-botocore \
    sshpass \
    net-tools \
    dnsutils \
    iputils-ping
ok "System packages installed"

# ─── 2. Install yq (YAML processor) ──────────────────────────────────────────
log "[2/14] Installing yq"
YQ_VERSION="v4.44.1"
wget -qO /usr/local/bin/yq \
    "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
chmod +x /usr/local/bin/yq
ok "yq $(yq --version) installed"

# ─── 3. HashiCorp APT repo (Packer + Terraform) ──────────────────────────────
log "[3/14] Adding HashiCorp APT repository"
wget -qO- https://apt.releases.hashicorp.com/gpg \
    | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/hashicorp.list
apt-get update -qq
ok "HashiCorp repo added"

# ─── 4. Install Packer ────────────────────────────────────────────────────────
log "[4/14] Installing Packer"
apt-get install -y packer
ok "Packer $(packer --version) installed"

# ─── 5. Install Terraform ─────────────────────────────────────────────────────
log "[5/14] Installing Terraform"
apt-get install -y terraform
ok "Terraform $(terraform --version | head -1) installed"

# ─── 6. Install Ansible ───────────────────────────────────────────────────────
log "[6/14] Installing Ansible"
add-apt-repository --yes --update ppa:ansible/ansible
apt-get install -y ansible
# Install useful Galaxy collections system-wide
ansible-galaxy collection install \
    community.general \
    community.crypto \
    community.proxmox \
    community.hashi_vault \
    ansible.posix \
    amazon.aws \
    --force
# Python libraries required by community.proxmox (proxmoxer) and
# community.hashi_vault (hvac) modules on the control node
apt-get install -y python3-proxmoxer python3-requests python3-hvac
ok "$(ansible --version | head -1) installed"

# ─── 7. Install AWS CLI v2 ────────────────────────────────────────────────────
log "[7/14] Installing AWS CLI v2"
AWSCLI_TMP=$(mktemp -d)
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
    -o "${AWSCLI_TMP}/awscliv2.zip"
unzip -q "${AWSCLI_TMP}/awscliv2.zip" -d "${AWSCLI_TMP}"
"${AWSCLI_TMP}/aws/install"
rm -rf "${AWSCLI_TMP}"
ok "AWS CLI $(aws --version 2>&1) installed"

# ─── 8. Install Azure CLI ─────────────────────────────────────────────────────
log "[8/14] Installing Azure CLI"
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
# This image is permanently pinned to Ubuntu 24.04 LTS ('noble') -- see
# automation-toolbox.pkrvars.hcl -- specifically because Microsoft's Azure
# CLI apt repo doesn't yet publish a release for 26.04's codename. Hardcoded
# rather than detected via lsb_release, since detection would silently mask
# the day this script is ever pointed at a different base image.
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] \
    https://packages.microsoft.com/repos/azure-cli/ noble main" \
    > /etc/apt/sources.list.d/azure-cli.list
apt-get update -qq
apt-get install -y azure-cli
ok "Azure CLI $(az --version 2>&1 | head -1) installed"

# ─── 9. Install Google Cloud CLI ──────────────────────────────────────────────
log "[9/14] Installing Google Cloud CLI"
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
    | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
# Google Cloud uses a fixed suite name (cloud-sdk main) so it works on any
# Ubuntu codename including resolute.
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] \
    https://packages.cloud.google.com/apt cloud-sdk main" \
    > /etc/apt/sources.list.d/google-cloud-sdk.list
apt-get update -qq
apt-get install -y google-cloud-cli
ok "Google Cloud CLI $(gcloud --version 2>&1 | head -1) installed"

# ─── 10. Install kubectl + Helm ───────────────────────────────────────────────
log "[10/14] Installing kubectl and Helm"

# kubectl — latest stable
KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
curl -fsSLo /usr/local/bin/kubectl \
    "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
chmod +x /usr/local/bin/kubectl
ok "kubectl ${KUBECTL_VERSION} installed"

# Helm — via official install script
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
ok "Helm $(helm version --short) installed"

# ─── 11. Install GitHub CLI ───────────────────────────────────────────────────
log "[11/14] Installing GitHub CLI"
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
    https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
apt-get update -qq
apt-get install -y gh
ok "GitHub CLI $(gh --version | head -1) installed"

# ─── 12. Install Docker CE ────────────────────────────────────────────────────
log "[12/14] Installing Docker CE"

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Same reasoning as the Azure CLI step above: this image is permanently
# pinned to 24.04 ('noble'), and Docker's apt repo doesn't yet publish a
# release for 26.04's codename either, so the codename is hardcoded rather
# than detected.
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
    https://download.docker.com/linux/ubuntu noble stable" \
    > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl start docker || true
ok "Docker $(docker --version) installed"

# ─── 13. Create toolbox user + workspace ──────────────────────────────────────
log "[13/14] Creating '${TOOLBOX_USER}' user and workspace"

if ! id "${TOOLBOX_USER}" &>/dev/null; then
    useradd \
        --shell /bin/bash \
        --create-home \
        --comment "Automation Toolbox service account" \
        "${TOOLBOX_USER}"
    ok "User '${TOOLBOX_USER}' created"
fi

# Passwordless sudo — needed to run packer builds and terraform applies
echo "${TOOLBOX_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${TOOLBOX_USER}"
chmod 0440 "/etc/sudoers.d/${TOOLBOX_USER}"
ok "Passwordless sudo configured"

usermod -aG docker "${TOOLBOX_USER}"
ok "Added '${TOOLBOX_USER}' to 'docker' group"

# SSH config — agent forwarding for private network hosts
TOOLBOX_SSH_DIR="/home/${TOOLBOX_USER}/.ssh"
mkdir -p "${TOOLBOX_SSH_DIR}"
cat > "${TOOLBOX_SSH_DIR}/config" << 'SSH_EOF'
Host *
    ServerAliveInterval   60
    ServerAliveCountMax    3
    ConnectTimeout        10
    ControlMaster         auto
    ControlPath           ~/.ssh/cm-%r@%h:%p
    ControlPersist        10m

Host 10.* 172.16.* 172.17.* 172.18.* 172.19.* 172.20.* 172.21.* 172.22.* 172.23.* 172.24.* 172.25.* 172.26.* 172.27.* 172.28.* 172.29.* 172.30.* 172.31.* 192.168.*
    StrictHostKeyChecking  no
    UserKnownHostsFile     /dev/null
    ForwardAgent           yes
SSH_EOF
chmod 700 "${TOOLBOX_SSH_DIR}"
chmod 600 "${TOOLBOX_SSH_DIR}/config"
chown -R "${TOOLBOX_USER}:${TOOLBOX_USER}" "${TOOLBOX_SSH_DIR}"

# Workspace directories
mkdir -p \
    "${TOOLBOX_HOME}/ansible" \
    "${TOOLBOX_HOME}/packer" \
    "${TOOLBOX_HOME}/terraform" \
    "${TOOLBOX_HOME}/logs"
chown -R "${TOOLBOX_USER}:${TOOLBOX_USER}" "${TOOLBOX_HOME}"

# ─── 14. Create personal admin login ──────────────────────────────────────────
log "[14/14] Creating personal admin login"

ADMIN_USERNAME="${ADMIN_USERNAME:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"
ADMIN_SSH_PUBLIC_KEY="${ADMIN_SSH_PUBLIC_KEY:-}"

if [[ -n "${ADMIN_USERNAME}" ]]; then
    if ! id "${ADMIN_USERNAME}" &>/dev/null; then
        useradd \
            --shell /bin/bash \
            --create-home \
            --comment "Personal admin login" \
            "${ADMIN_USERNAME}"
        ok "User '${ADMIN_USERNAME}' created"
    fi

    usermod -aG sudo "${ADMIN_USERNAME}"
    ok "Added '${ADMIN_USERNAME}' to 'sudo' group (password required)"

    if [[ -n "${ADMIN_PASSWORD}" ]]; then
        echo "${ADMIN_USERNAME}:${ADMIN_PASSWORD}" | chpasswd
        ok "Password set for '${ADMIN_USERNAME}'"
    else
        log "No ADMIN_PASSWORD provided — '${ADMIN_USERNAME}' has no password set"
    fi

    if [[ -n "${ADMIN_SSH_PUBLIC_KEY}" ]]; then
        ADMIN_SSH_DIR="/home/${ADMIN_USERNAME}/.ssh"
        mkdir -p "${ADMIN_SSH_DIR}"
        echo "${ADMIN_SSH_PUBLIC_KEY}" > "${ADMIN_SSH_DIR}/authorized_keys"
        chmod 700 "${ADMIN_SSH_DIR}"
        chmod 600 "${ADMIN_SSH_DIR}/authorized_keys"
        chown -R "${ADMIN_USERNAME}:${ADMIN_USERNAME}" "${ADMIN_SSH_DIR}"
        ok "SSH public key installed for '${ADMIN_USERNAME}'"
    else
        log "No ADMIN_SSH_PUBLIC_KEY provided — '${ADMIN_USERNAME}' has no SSH key configured"
    fi
else
    log "No ADMIN_USERNAME provided — skipping personal admin login creation"
fi

# Bootstrap script — run once after first VM boot
cat > "${TOOLBOX_HOME}/bootstrap.sh" << 'BOOTSTRAP_EOF'
#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — Run once after first boot of the automation toolbox VM
# =============================================================================
set -euo pipefail

TOOLBOX_USER="toolbox"
SSH_KEY="/home/${TOOLBOX_USER}/.ssh/id_ed25519"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Automation Toolbox Bootstrap"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo " Installed tools:"
echo "   Ansible   : $(ansible --version | head -1)"
echo "   Packer    : $(packer --version)"
echo "   Terraform : $(terraform --version | head -1)"
echo "   AWS CLI   : $(aws --version 2>&1)"
echo "   Azure CLI : $(az --version 2>&1 | head -1)"
echo "   GCP CLI   : $(gcloud --version 2>&1 | head -1)"
echo "   kubectl   : $(kubectl version --client --short 2>/dev/null || kubectl version --client)"
echo "   Helm      : $(helm version --short)"
echo "   GitHub CLI: $(gh --version | head -1)"
echo "   Docker    : $(docker --version)"
echo ""

# Generate SSH key for the toolbox user
if [[ ! -f "${SSH_KEY}" ]]; then
    echo "[1/2] Generating SSH key pair for the '${TOOLBOX_USER}' user..."
    sudo -u "${TOOLBOX_USER}" ssh-keygen \
        -t ed25519 \
        -C "${TOOLBOX_USER}@$(hostname)" \
        -f "${SSH_KEY}" \
        -N ""
    echo ""
fi

echo "[2/2] Public key — add this to managed hosts and GitHub:"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat "${SSH_KEY}.pub"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo " Next steps:"
echo "  1. Clone your monorepo:  cd /opt/toolbox && git clone https://github.com/IT-Architect-UK/monorepo.git"
echo "  2. Authenticate AWS:     aws configure"
echo "  3. Authenticate Azure:   az login"
echo "  4. Authenticate GCP:     gcloud auth login"
echo "  5. Authenticate GitHub:  gh auth login"
echo "  6. Run a packer build:   cd /opt/toolbox/monorepo/automation/packer && packer build ..."
echo ""
BOOTSTRAP_EOF

chmod +x "${TOOLBOX_HOME}/bootstrap.sh"
chown "${TOOLBOX_USER}:${TOOLBOX_USER}" "${TOOLBOX_HOME}/bootstrap.sh"
ok "Bootstrap script written to ${TOOLBOX_HOME}/bootstrap.sh"

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════"
echo " Automation Toolbox provisioning complete!"
echo ""
echo "  Ansible   : $(ansible --version | head -1)"
echo "  Packer    : $(packer --version)"
echo "  Terraform : $(terraform --version | head -1)"
echo "  AWS CLI   : $(aws --version 2>&1)"
echo "  GCloud CLI: $(gcloud --version 2>&1 | head -1)"
echo "  Azure CLI : $(az --version 2>&1 | head -1)"
echo "  GCP CLI   : $(gcloud --version 2>&1 | head -1)"
echo "  kubectl   : $(kubectl version --client 2>&1 | head -1)"
echo "  Helm      : $(helm version --short)"
echo "  GitHub CLI: $(gh --version | head -1)"
echo "  Docker    : $(docker --version)"
echo "  yq        : $(yq --version)"
echo ""
echo "  After first boot, run:"
echo "    sudo bash ${TOOLBOX_HOME}/bootstrap.sh"
echo "══════════════════════════════════════════════════════════"
