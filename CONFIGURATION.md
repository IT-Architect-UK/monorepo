# Configuration Guide

This guide explains how to configure credentials and settings for every platform covered in this repository **before running any scripts**.

Scripts in this repo never hardcode credentials. Instead they read from:
- **Environment variables** (works locally and in GitHub Actions CI/CD)
- **`.env` files** (local only — never committed to GitHub)
- **CLI flags** (pass values directly when running a script)

---

## Quick Start — Which Section Do You Need?

| I want to... | Go to |
|---|---|
| Deploy VMs on Proxmox | [Proxmox Setup](#proxmox-ve) |
| Deploy VMs on VMware vCenter/ESXi | [VMware Setup](#vmware-vcenter--esxi) |
| Build images with Packer | [Packer Setup](#packer) |
| Run Ansible playbooks | [Ansible Setup](#ansible) |
| Use AWS (EC2, S3, ACM, Backup) | [AWS Setup](#aws) |
| Use Azure (VMs, Key Vault, Monitor) | [Azure Setup](#azure) |
| Use Google Cloud (GCP) | [GCP Setup](#gcp) |
| Run scripts via GitHub Actions CI/CD | [GitHub Actions Setup](#github-actions-cicd) |

---

## How the `.env` File Pattern Works

Every script directory has a `.env.example` file. Copy it to `.env` and fill in your values:

```bash
cd infrastructure/hypervisors/proxmox
cp .env.example .env
nano .env          # Fill in your values
source .env        # Load into your shell session
```

The `.env` file is in `.gitignore` so it **can never be accidentally committed to GitHub**.

To avoid sourcing it every time, add it to your shell profile:
```bash
echo "source ~/path/to/repo/infrastructure/hypervisors/proxmox/.env" >> ~/.bashrc
```

---

## Proxmox VE

Scripts in `infrastructure/hypervisors/proxmox/` and `image-maintenance/linux/` run **directly on the Proxmox host**. There is no remote connection required — you either SSH into the host first or use the Proxmox web UI shell.

### Step 1 — SSH into your Proxmox host

```bash
ssh root@<your-proxmox-ip>
# Example: ssh root@192.168.1.10
```

Or use: **Proxmox Web UI → your node → Shell**

### Step 2 — Find your storage pool name

```bash
pvesm status
# Shows all storage pools. Note the name in the first column.
# Common values: local-lvm, local-zfs, local
```

Or: **Proxmox Web UI → Datacenter → Storage**

### Step 3 — Find your node name

```bash
hostname
# Or:
pvesh get /nodes --output-format=text
```

Or: **Proxmox Web UI → left panel → the name under "Datacenter"**

### Step 4 — Set up your defaults (optional but recommended)

```bash
cd /path/to/repo/infrastructure/hypervisors/proxmox
cp .env.example .env
nano .env
source .env
```

### Step 5 — Run a script

```bash
# Deploy a new Ubuntu VM (uses defaults from .env or prompts)
./vms/deploy-ubuntu-2404.sh

# Override specific values with flags:
./vms/deploy-ubuntu-2404.sh --vmid 110 --name "web01" --storage "local-lvm"

# See all options:
./vms/deploy-ubuntu-2404.sh --help
```

### Required values at a glance

| Variable | Where to find it | Example |
|---|---|---|
| Storage pool | `pvesm status` or Proxmox UI → Storage | `local-lvm` |
| Node name | `hostname` or Proxmox UI left panel | `pve` |
| Bridge name | `ip link show` or Proxmox UI → Network | `vmbr0` |
| SSH public key | `~/.ssh/id_ed25519.pub` | generate with `ssh-keygen -t ed25519` |

---

## VMware vCenter / ESXi

Scripts in `infrastructure/hypervisors/vmware/` run from a Windows machine with **VMware PowerCLI** installed.

### Step 1 — Install PowerCLI

```powershell
Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
```

### Step 2 — Find your vCenter details

| What you need | Where to find it |
|---|---|
| vCenter hostname/IP | The address you use to log into the vCenter web UI |
| Datacenter name | vCenter UI → Home → Hosts and Clusters → top-level object name |
| Cluster name | vCenter UI → Home → Hosts and Clusters → expand datacenter |
| Datastore name | vCenter UI → Home → Storage → select a datastore |
| Network name | vCenter UI → Home → Networking → your port group |

### Step 3 — Set your credentials

```powershell
# Option A — Set for this PowerShell session only
$env:VCENTER_HOST     = "vcenter.homelab.local"
$env:VCENTER_USERNAME = "administrator@vsphere.local"
$env:VCENTER_PASSWORD = "YourPassword"

# Option B — Load from .env file
Get-Content .env.example | Where-Object { $_ -notmatch '^#' -and $_ -ne '' } |
  ForEach-Object { $n,$v = $_ -split '=',2; Set-Item "env:$n" $v.Trim('"') }
```

### Step 4 — Run a script

```powershell
# Connect to vCenter and deploy from template
.\provisioning\deploy-vm-from-template.ps1 `
  -vCenterServer $env:VCENTER_HOST `
  -Username $env:VCENTER_USERNAME `
  -Password $env:VCENTER_PASSWORD `
  -CsvPath ".\vms-to-deploy.csv"
```

---

## Packer

Packer templates are in `automation/packer/`. They can build images on Proxmox, VMware, AWS, Azure, and GCP.

### Step 1 — Install Packer

```bash
# Linux/macOS
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install packer

# Windows (via Chocolatey)
choco install packer

# macOS
brew tap hashicorp/tap && brew install hashicorp/tap/packer
```

### Step 2 — Set credentials

```bash
cd automation/packer
cp .env.example .env
nano .env                  # Fill in Proxmox/VMware/cloud credentials
source .env                # Load PKR_VAR_* variables into your shell
```

### Step 3 — Install plugins (once)

```bash
packer init .
```

### Step 4 — Update the var file for your environment

```bash
# Edit the homelab var file with YOUR Proxmox/VMware details
nano environments/homelab.pkrvars.hcl
```

### Step 5 — Validate (no changes made)

```bash
packer validate \
  -var-file="environments/homelab.pkrvars.hcl" \
  ubuntu-2404-proxmox.pkr.hcl
```

### Step 6 — Build

```bash
packer build \
  -var-file="environments/homelab.pkrvars.hcl" \
  ubuntu-2404-proxmox.pkr.hcl
```

### Required variables (non-sensitive — go in `.pkrvars.hcl`)

| Variable | Where to find it | Example |
|---|---|---|
| `proxmox_url` | Your Proxmox IP + `/api2/json` | `https://192.168.1.10:8006/api2/json` |
| `proxmox_node` | `hostname` on Proxmox host | `pve` |
| `proxmox_storage_pool` | `pvesm status` | `local-lvm` |
| `proxmox_iso_storage` | Proxmox UI → Storage | `local` |
| `ubuntu_iso_url` | Proxmox UI → local → ISO Images → right-click → path | `local:iso/ubuntu-24.04-live-server-amd64.iso` |
| `vsphere_server` | vCenter hostname | `vcenter.homelab.local` |
| `vsphere_datacenter` | vCenter UI → Hosts and Clusters | `Datacenter` |
| `aws_region` | Your preferred AWS region | `eu-west-2` |

### Sensitive variables (go in `.env` — never in `.pkrvars.hcl`)

| Variable | Set as |
|---|---|
| Proxmox password | `export PKR_VAR_proxmox_password="..."` |
| vCenter password | `export PKR_VAR_vsphere_password="..."` |
| Azure subscription ID | `export PKR_VAR_azure_subscription_id="..."` |

---

## Ansible

Playbooks are in `automation/ansible/`. Run them from the **Ansible control node** (built by the Packer template, or any machine with Ansible installed).

### Step 1 — Edit the inventory

Add your servers to `automation/ansible/inventory/hosts.yml`:

```yaml
all:
  children:
    web_servers:
      hosts:
        web-01:
          ansible_host: 192.168.1.101    # ← Replace with your server IP
    db_servers:
      hosts:
        db-01:
          ansible_host: 192.168.1.110    # ← Replace with your server IP
```

### Step 2 — Set shared variables

Edit `automation/ansible/inventory/group_vars/all.yml`:
- `admin_user` — the username Ansible will use on managed hosts
- `ssh_port` — usually 22
- `ufw_rules` — ports to open in the firewall

### Step 3 — Distribute your SSH key

```bash
# This must be done once per managed host.
# -k prompts for the managed host's password (only needed this first time):
ansible-playbook playbooks/distribute-ssh-key.yml -k
```

### Step 4 — Test connectivity

```bash
ansible all -m ping
# Expected: each host returns "pong"
```

### Step 5 — Run a playbook

```bash
ansible-playbook playbooks/server-baseline.yml
ansible-playbook playbooks/server-baseline.yml --limit web_servers   # target one group
ansible-playbook playbooks/server-baseline.yml --check               # dry run
```

---

## AWS

Scripts in `image-maintenance/cloud/aws/`, `backup/cloud/aws/`, `security/tls/cloud/`, and `monitoring/cloud/aws/` all use the **AWS CLI**.

### Step 1 — Install the AWS CLI

```bash
# Linux
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install

# macOS
brew install awscli

# Windows
winget install Amazon.AWSCLI
```

### Step 2 — Configure credentials

```bash
aws configure
# Prompts for:
#   AWS Access Key ID:     (from IAM → Users → your user → Security credentials)
#   AWS Secret Access Key: (created at same time as Access Key)
#   Default region name:   eu-west-2   (or your preferred region)
#   Default output format: json
```

> **Where to create an Access Key:**  
> AWS Console → IAM → Users → your username → Security credentials tab → Create access key

> **Minimum IAM permissions needed** (depends on script):  
> - Image maintenance: `ec2:*`, `ssm:SendCommand`, `iam:PassRole`  
> - Backup: `backup:*`, `iam:CreateRole`, `iam:AttachRolePolicy`  
> - TLS: `acm:*`, `route53:*` (for DNS validation)  
> - Monitoring: `cloudwatch:*`, `ssm:GetParameter`

### Step 3 — Verify

```bash
aws sts get-caller-identity
# Should return your Account ID, UserID, and ARN
```

### Step 4 — Run a script

```bash
./image-maintenance/cloud/aws/build-golden-ami.sh --region eu-west-2
```

---

## Azure

Scripts in `image-maintenance/cloud/azure/`, `security/tls/cloud/`, and `monitoring/cloud/azure/` use the **Azure CLI**.

### Step 1 — Install Azure CLI

```bash
# Linux
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# macOS
brew install azure-cli

# Windows
winget install Microsoft.AzureCLI
```

### Step 2 — Log in

```bash
az login
# Opens a browser window — sign in with your Azure account
```

### Step 3 — Select your subscription

```bash
az account list --output table        # List all subscriptions
az account set --subscription "<name or ID>"
az account show                       # Confirm the right one is active
```

### Step 4 — Find resource group and location

```bash
az group list --output table          # Lists all resource groups
az account list-locations --output table  # Lists all regions
```

### Step 5 — Run a script

```bash
./image-maintenance/cloud/azure/update-managed-image.sh \
  --resource-group "my-rg" \
  --image-name "ubuntu-2404-golden" \
  --location "uksouth"
```

---

## GCP

Scripts in `image-maintenance/cloud/gcp/`, `security/tls/cloud/`, and `monitoring/cloud/gcp/` use the **Google Cloud CLI**.

### Step 1 — Install gcloud CLI

```bash
# Linux
curl https://sdk.cloud.google.com | bash
exec -l $SHELL

# macOS
brew install --cask google-cloud-sdk

# Windows
# Download installer from: https://cloud.google.com/sdk/docs/install
```

### Step 2 — Log in

```bash
gcloud auth login
gcloud auth application-default login   # For tools like Packer and Terraform
```

### Step 3 — Set your project

```bash
gcloud projects list                           # List all projects
gcloud config set project YOUR_PROJECT_ID     # Set the active project
gcloud config list                            # Confirm settings
```

### Step 4 — Run a script

```bash
./image-maintenance/cloud/gcp/update-machine-image.sh \
  --project "my-project-id" \
  --zone "europe-west2-a"
```

---

## GitHub Actions CI/CD

For scripts you want to run automatically (scheduled builds, auto-patching), store credentials as **GitHub Secrets** — they're encrypted and never visible in logs.

### Step 1 — Add secrets to your repo

Go to: **GitHub → your repo → Settings → Secrets and variables → Actions → New repository secret**

Add these secrets based on which platforms you use:

**Proxmox:**
| Secret name | Value |
|---|---|
| `PROXMOX_URL` | `https://your-proxmox-ip:8006/api2/json` |
| `PROXMOX_USERNAME` | `root@pam` |
| `PROXMOX_PASSWORD` | your Proxmox password |

> **Note:** Proxmox home labs are typically not internet-accessible. For GitHub Actions to reach Proxmox you'd need a self-hosted runner on your network, or a VPN/tunnel. See the GitHub Actions workflow examples in `.github/workflows/`.

**AWS:**
| Secret name | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | your IAM access key |
| `AWS_SECRET_ACCESS_KEY` | your IAM secret key |
| `AWS_DEFAULT_REGION` | `eu-west-2` |

**Azure:**
| Secret name | Value |
|---|---|
| `AZURE_CREDENTIALS` | JSON output of `az ad sp create-for-rbac --sdk-auth` |

**GCP:**
| Secret name | Value |
|---|---|
| `GCP_PROJECT_ID` | your project ID |
| `GCP_SA_KEY` | base64-encoded service account JSON key |

### Step 2 — GitHub Actions workflows

Pre-built workflow files are in `.github/workflows/`:
- `validate.yml` — runs syntax checks on every push/PR
- `packer-build-aws.yml` — monthly automated AMI build
- `packer-build-azure.yml` — monthly Azure image build
- `packer-build-gcp.yml` — monthly GCP image build

---

## Security Best Practices

1. **Never commit `.env` files** — `.gitignore` protects against this, but double-check with `git status` before pushing
2. **Use the least-privilege IAM/RBAC** — only grant the permissions each script actually needs
3. **Use API tokens instead of root passwords** where possible (Proxmox, vCenter)
4. **Rotate credentials regularly** — especially if you share the repo with others
5. **Use a secrets manager** for production — HashiCorp Vault, AWS Secrets Manager, Azure Key Vault, or GCP Secret Manager instead of `.env` files
