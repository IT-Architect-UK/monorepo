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
log "[1/13] System prerequisites"
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
log "[2/13] Installing yq"
YQ_VERSION="v4.44.1"
wget -qO /usr/local/bin/yq \
    "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64"
chmod +x /usr/local/bin/yq
ok "yq $(yq --version) installed"

# ─── 3. HashiCorp APT repo (Packer + Terraform) ──────────────────────────────
log "[3/13] Adding HashiCorp APT repository"
wget -qO- https://apt.releases.hashicorp.com/gpg \
    | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
    https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/hashicorp.list
apt-get update -qq
ok "HashiCorp repo added"

# ─── 4. Install Packer ────────────────────────────────────────────────────────
log "[4/13] Installing Packer"
apt-get install -y packer
ok "Packer $(packer --version) installed"

# ─── 5. Install Terraform ─────────────────────────────────────────────────────
log "[5/13] Installing Terraform"
apt-get install -y terraform
ok "Terraform $(terraform --version | head -1) installed"

# ─── 6. Install Ansible ───────────────────────────────────────────────────────
log "[6/13] Installing Ansible"
add-apt-repository --yes --update ppa:ansible/ansible
apt-get install -y ansible
# Install useful Galaxy collections system-wide
ansible-galaxy collection install \
    community.general \
    community.crypto \
    ansible.posix \
    amazon.aws \
    --force
ok "$(ansible --version | head -1) installed"

# ─── 7. Install AWS CLI v2 ────────────────────────────────────────────────────
log "[7/13] Installing AWS CLI v2"
AWSCLI_TMP=$(mktemp -d)
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
    -o "${AWSCLI_TMP}/awscliv2.zip"
unzip -q "${AWSCLI_TMP}/awscliv2.zip" -d "${AWSCLI_TMP}"
"${AWSCLI_TMP}/aws/install"
rm -rf "${AWSCLI_TMP}"
ok "AWS CLI $(aws --version 2>&1) installed"

# ─── 8. Install Azure CLI ─────────────────────────────────────────────────────
log "[8/13] Installing Azure CLI"
curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
# Microsoft's apt repo doesn't always have a release for the latest Ubuntu
# codename; fall back to noble (24.04) for any unsupported codename.
_AZ_DISTRO=$(lsb_release -cs)
case "${_AZ_DISTRO}" in
    focal|jammy|noble) : ;;
    *)                 _AZ_DISTRO="noble" ;;
esac
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] \
    https://packages.microsoft.com/repos/azure-cli/ ${_AZ_DISTRO} main" \
    > /etc/apt/sources.list.d/azure-cli.list
apt-get update -qq
apt-get install -y azure-cli
ok "Azure CLI $(az --version 2>&1 | head -1) installed"

# ─── 9. Install Google Cloud CLI ──────────────────────────────────────────────
log "[9/13] Installing Google Cloud CLI"
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
log "[10/13] Installing kubectl and Helm"

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
log "[11/13] Installing GitHub CLI"
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
    https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list
apt-get update -qq
apt-get install -y gh
ok "GitHub CLI $(gh --version | head -1) installed"

# ─── 12. Install Docker CE ────────────────────────────────────────────────────
log "[12/13] Installing Docker CE"

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# Fall back to the newest codename Docker's repo actually publishes if this
# Ubuntu release isn't there yet (same pattern used for the Azure CLI repo below).
_DOCKER_CODENAME=$(lsb_release -cs)
case "${_DOCKER_CODENAME}" in
    focal|jammy|noble) : ;;
    *)                  _DOCKER_CODENAME="noble" ;;
esac

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
    https://download.docker.com/linux/ubuntu ${_DOCKER_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable docker
systemctl start docker || true
ok "Docker $(docker --version) installed"

# ─── 13. Create toolbox user + workspace ──────────────────────────────────────
log "[13/13] Creating '${TOOLBOX_USER}' user and workspace"

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

# Authorized key — SSH password auth is disabled by provision.sh, so this is
# the only way to actually log in as this user once the build is sealed.
TOOLBOX_SSH_PUBLIC_KEY="${TOOLBOX_SSH_PUBLIC_KEY:-}"
if [[ -n "${TOOLBOX_SSH_PUBLIC_KEY}" ]]; then
    echo "${TOOLBOX_SSH_PUBLIC_KEY}" > "${TOOLBOX_SSH_DIR}/authorized_keys"
    chmod 600 "${TOOLBOX_SSH_DIR}/authorized_keys"
    ok "SSH public key installed for '${TOOLBOX_USER}'"
else
    log "No TOOLBOX_SSH_PUBLIC_KEY provided — '${TOOLBOX_USER}' will have no SSH access"
fi

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
