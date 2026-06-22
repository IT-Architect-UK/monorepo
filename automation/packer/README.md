# Packer — Automated Machine Image Builds

[HashiCorp Packer](https://www.packer.io/) automates the creation of identical machine images across multiple platforms from a single configuration file. Instead of manually launching a VM, patching it, and converting it to a template, Packer does the entire pipeline in a single command.

## 🤔 Why Packer?

| Manual approach | With Packer |
|----------------|-------------|
| Launch VM, SSH in, patch manually | `packer build ubuntu-2404-aws.pkr.hcl` |
| Steps aren't documented | Everything is in version-controlled HCL files |
| Different process per platform | One template structure, five platforms |
| Easy to forget a step | Reproducible, auditable, CI/CD ready |
| Rebuilt from scratch each time | Fast: starts from latest base image, adds only your changes |

Packer is the industry standard for immutable infrastructure — the image is built once, tested, and deployed many times. Nothing changes after deployment.

## 🔗 How It Connects to the Rest of This Repo

```
Packer (this directory)
    │
    ├── calls ──► scripts/provision.sh   (OS updates, hardening)
    ├── calls ──► ../ansible/playbooks/server-baseline.yml  (Ansible role)
    ├── calls ──► scripts/cleanup.sh     (image sealing)
    │
    └── outputs──► Template / AMI / Managed Image / GCP Image
                        │
                        └── deployed by ──► Terraform (next step!)
```

Your Ansible roles are reused inside Packer — no duplication. The same `server-baseline` role that hardens a running server also hardens the golden image.

## 📁 Folder Structure

```
packer/
├── variables.pkr.hcl              # All variable definitions (shared by all templates)
├── ubuntu-2404-proxmox.pkr.hcl   # Build Proxmox template from ISO
├── ubuntu-2404-vmware.pkr.hcl    # Build VMware vSphere template from ISO
├── ubuntu-2404-aws.pkr.hcl       # Build AWS AMI
├── ubuntu-2404-azure.pkr.hcl     # Build Azure Managed Image
├── ubuntu-2404-gcp.pkr.hcl       # Build GCP custom image
├── scripts/
│   ├── provision.sh               # Runs inside the build VM: updates, tools, hardening
│   └── cleanup.sh                 # Runs last: seals the image (removes machine-unique data)
├── http/
│   ├── user-data                  # Ubuntu autoinstall config (unattended OS install)
│   └── meta-data                  # Required by cloud-init NoCloud datasource
└── environments/
    ├── homelab.pkrvars.hcl        # Variable values for home lab builds
    └── production.pkrvars.hcl     # Variable values for production builds
```

## 🚀 Getting Started

### 1. Install Packer

```bash
# Ubuntu / Debian
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install packer

# macOS
brew tap hashicorp/tap && brew install hashicorp/tap/packer

# Verify
packer version
```

### 2. Install plugins

Run once in this directory — downloads the platform-specific Packer plugins:

```bash
packer init .
```

### 3. Set credentials

Never hardcode passwords. Use environment variables:

```bash
# Proxmox
export PKR_VAR_proxmox_password="your-proxmox-password"

# VMware
export PKR_VAR_vsphere_password="your-vcenter-password"

# AWS — uses your existing AWS CLI config, or:
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."

# Azure — uses your Azure CLI session (az login), or:
export PKR_VAR_azure_subscription_id="your-sub-id"
export ARM_CLIENT_ID="..."
export ARM_CLIENT_SECRET="..."
export ARM_TENANT_ID="..."

# GCP — uses Application Default Credentials (gcloud auth application-default login), or:
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
```

### 4. Build your first image

```bash
# Validate the template (catches syntax errors without building)
packer validate ubuntu-2404-aws.pkr.hcl

# Build with default variables
packer build ubuntu-2404-aws.pkr.hcl

# Build with your home lab settings
packer build -var-file="environments/homelab.pkrvars.hcl" ubuntu-2404-proxmox.pkr.hcl

# Build with a specific image name
packer build -var "image_name=my-custom-image" ubuntu-2404-aws.pkr.hcl

# Enable debug output (shows every command Packer runs)
PACKER_LOG=1 packer build ubuntu-2404-aws.pkr.hcl
```

## 📋 Platform Quick Reference

| Platform | Template | Auth method | Output |
|----------|----------|-------------|--------|
| **Proxmox** | `ubuntu-2404-proxmox.pkr.hcl` | `PKR_VAR_proxmox_password` | VM Template (ID 9000) |
| **VMware** | `ubuntu-2404-vmware.pkr.hcl` | `PKR_VAR_vsphere_password` | vSphere Template |
| **AWS** | `ubuntu-2404-aws.pkr.hcl` | `aws configure` | AMI |
| **Azure** | `ubuntu-2404-azure.pkr.hcl` | `az login` | Managed Image |
| **GCP** | `ubuntu-2404-gcp.pkr.hcl` | `gcloud auth` | Custom Image |

## 🔄 Build Pipeline (what happens during `packer build`)

```
packer build ubuntu-2404-aws.pkr.hcl
      │
      ├─ [1] Source: Find latest Ubuntu 24.04 AMI from Canonical
      ├─ [2] Launch temporary EC2 t3.micro instance
      ├─ [3] Wait for SSH to become available
      │
      ├─ [4] Provisioner: scripts/provision.sh
      │         ├── apt-get update && upgrade
      │         ├── Install common tools
      │         ├── Harden SSH
      │         ├── Configure UFW firewall
      │         └── Configure cloud-init
      │
      ├─ [5] Provisioner: Ansible server-baseline role
      │         ├── Apply all tasks from roles/common/
      │         ├── Configure fail2ban
      │         └── Set timezone / NTP
      │
      ├─ [6] Provisioner: scripts/cleanup.sh
      │         ├── Clean cloud-init cache
      │         ├── Remove SSH host keys
      │         ├── Reset machine-id
      │         └── Clear logs and temp files
      │
      ├─ [7] Stop instance and create AMI snapshot
      ├─ [8] Tag AMI with metadata
      ├─ [9] Terminate source instance
      └─ [10] Write packer-manifest.json with AMI ID
```

Total build time: ~10-15 minutes for AWS, ~20-40 minutes for Proxmox/VMware (ISO download + OS install).

## 🏗️ CI/CD Integration

Run Packer builds automatically in GitHub Actions, GitLab CI, or Jenkins:

```yaml
# .github/workflows/build-ami.yml
name: Build Golden AMI

on:
  schedule:
    - cron: '0 2 1 * *'   # First day of each month at 2am
  push:
    paths:
      - 'automation/packer/**'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Packer
        uses: hashicorp/setup-packer@main
        with:
          version: latest

      - name: Init Packer plugins
        run: packer init automation/packer/

      - name: Build AMI
        run: packer build automation/packer/ubuntu-2404-aws.pkr.hcl
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
```

## ☁️ Cloud Equivalents

| Packer concept | AWS equivalent | Azure equivalent | GCP equivalent |
|---------------|----------------|-----------------|----------------|
| `amazon-ebs` builder | EC2 Image Builder | Azure Image Builder | Cloud Build |
| Output AMI | AMI | Managed Image | Custom Image |
| `source_ami_filter` | Latest AMI from family | Latest marketplace image | `image_family` lookup |
| Provisioner | EC2 User Data (limited) | Custom Script Extension | Startup Script |
| `packer-manifest.json` | SSM Parameter Store | Azure DevOps artifact | Artifact Registry |

## ❓ Troubleshooting

**`packer init` fails?**
→ Ensure internet access and that you're running Packer 1.10+: `packer version`

**SSH timeout during Proxmox/VMware build?**
→ The autoinstall can take 15-25 minutes. Increase `ssh_timeout` to `"45m"`.
→ Check the VM console in Proxmox/vCenter to see if the install is progressing.

**AWS: "no valid credential sources"?**
→ Run `aws configure` or set `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY` env vars.

**VMware: insecure_connection error?**
→ Either set `insecure_connection = true` (lab only) or add your vCenter certificate to the trusted store.

**Build VM IP not found (Proxmox)?**
→ Ensure `qemu-guest-agent` is installed and enabled in the template. Packer queries it for the IP address.

**packer-manifest.json not found?**
→ The manifest is written to the directory where you ran `packer build`. Check there.

## 📚 Further Reading

- [Packer Documentation](https://developer.hashicorp.com/packer/docs)
- [Proxmox Plugin Docs](https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox)
- [vSphere Plugin Docs](https://developer.hashicorp.com/packer/integrations/hashicorp/vsphere)
- [Amazon EBS Builder Docs](https://developer.hashicorp.com/packer/integrations/hashicorp/amazon/latest/components/builder/ebs)
- [Ubuntu Autoinstall Reference](https://ubuntu.com/server/docs/install/autoinstall-reference)
- [Packer + Ansible integration](https://developer.hashicorp.com/packer/integrations/hashicorp/ansible)
