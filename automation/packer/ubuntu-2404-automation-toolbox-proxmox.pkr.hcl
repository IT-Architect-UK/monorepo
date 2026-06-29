###############################################################################
# Packer Template: Ubuntu 24.04 Automation Toolbox — Proxmox
#
# PURPOSE
#   Builds a Proxmox VM template that is ready to use as a centralised
#   automation management host. On first boot the VM has:
#     • Ansible        — configuration management & orchestration
#     • Packer         — VM image building (can build MORE images from this host)
#     • Terraform      — infrastructure as code
#     • AWS CLI v2     — Amazon Web Services management
#     • Azure CLI      — Microsoft Azure management
#     • kubectl        — Kubernetes cluster management
#     • Helm           — Kubernetes package manager
#     • GitHub CLI     — repository and PR management from the CLI
#     • Python 3       — with boto3, azure-identity, google-cloud libraries
#     • Docker CE      — container build and run
#     • jq / yq        — JSON and YAML processing
#
# USAGE
#   packer init .
#   packer build \
#     -var-file="environments/homelab.pkrvars.hcl" \
#     -var-file="environments/automation-toolbox.pkrvars.hcl" \
#     ubuntu-2404-automation-toolbox-proxmox.pkr.hcl
#
# WHAT HAPPENS NEXT
#   1. Packer creates a Proxmox template called "automation-toolbox-<timestamp>"
#   2. Clone the template to create your management VM
#   3. SSH in and run: sudo bash /opt/toolbox/bootstrap.sh
#   4. Use this VM to run Packer builds, Terraform plans, and Ansible playbooks
###############################################################################

packer {
  required_version = ">= 1.10.0"
  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
    ansible = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

# ─── Local values ─────────────────────────────────────────────────────────────
locals {
  timestamp  = formatdate("YYYYMMDD-HHmm", timestamp())
  image_name = "automation-toolbox-${local.timestamp}"
}

# ─── Source: Proxmox ISO ──────────────────────────────────────────────────────
source "proxmox-iso" "automation-toolbox" {

  # ── Proxmox connection ──────────────────────────────────────────────────────
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  # ── VM identity ─────────────────────────────────────────────────────────────
  vm_id                = var.proxmox_vm_id
  vm_name              = local.image_name
  template_name        = local.image_name
  template_description = "Ubuntu 24.04 Automation Toolbox | Built ${local.timestamp} by Packer | Tools: Ansible, Packer, Terraform, AWS CLI, Azure CLI, kubectl, Helm, Docker, GitHub CLI"

  # ── ISO source ──────────────────────────────────────────────────────────────
  # Pre-uploaded ISO on Proxmox storage (set ubuntu_iso_file in homelab.pkrvars.hcl)
  iso_file         = var.ubuntu_iso_file
  iso_storage_pool = var.proxmox_iso_storage
  unmount_iso      = true

  # ── VM hardware ─────────────────────────────────────────────────────────────
  # Toolbox: 4 vCPU / 4 GB RAM — runs Packer builds and Terraform plans locally
  cores          = var.vm_cpu_count
  memory         = var.vm_memory_mb
  os             = "l26"
  qemu_agent     = true
  scsi_controller = "virtio-scsi-single"

  disks {
    disk_size    = "${var.vm_disk_gb}G"
    format       = "raw"
    storage_pool = var.proxmox_storage_pool
    type         = "virtio"
  }

  network_adapters {
    bridge   = "vmbr0"
    model    = "virtio"
    firewall = false
  }

  # ── EFI / BIOS ──────────────────────────────────────────────────────────────
  efi_config {
    efi_storage_pool  = var.proxmox_storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = true
  }
  bios = "ovmf"

  # ── Autoinstall (Ubuntu unattended install) ──────────────────────────────────
  # user-data and meta-data attached as CD-ROM — no HTTP server required.
  additional_iso_files {
    cd_files         = ["./http/user-data", "./http/meta-data"]
    cd_label         = "cidata"
    iso_storage_pool = var.proxmox_iso_storage
    unmount          = true
  }

  boot_command = [
    "<wait3>",
    "c<wait>",
    "linux /casper/vmlinuz --- autoinstall ds=nocloud<wait>",
    "<enter><wait>",
    "initrd /casper/initrd<wait>",
    "<enter><wait>",
    "boot<enter>"
  ]
  boot_wait = "5s"

  # ── SSH (Packer communicator) ────────────────────────────────────────────────
  communicator           = "ssh"
  ssh_username           = var.ssh_username
  ssh_password           = var.ssh_password
  ssh_timeout            = "45m"    # Extra time — lots of packages to install
  ssh_handshake_attempts = 50
}

# ─── Build ────────────────────────────────────────────────────────────────────
build {
  name    = "automation-toolbox"
  sources = ["source.proxmox-iso.automation-toolbox"]

  # 1. Base OS hardening (UFW, fail2ban, SSH hardening — same as every image)
  # Upload helper scripts used by provision.sh
  provisioner "file" {
    sources = [
      "${path.root}/../../infrastructure/servers/linux/configuration/apply-branding.sh",
      "${path.root}/../../infrastructure/servers/linux/configuration/disable-cloud-init.sh",
      "${path.root}/../../infrastructure/servers/linux/configuration/disable-ipv6.sh",
      "${path.root}/../../infrastructure/networking/firewall/setup-iptables.sh",
      "${path.root}/../../infrastructure/servers/linux/configuration/sync-monorepo.sh",
    ]
    destination = "/tmp/"
  }

  provisioner "shell" {
    script          = "scripts/provision.sh"
    execute_command = "sudo bash {{.Path}}"
    pause_before    = "10s"
    environment_vars = [
      "HYPERVISOR=proxmox",
      "COMPANY_NAME=${var.vm_company_name}",
    ]
  }

  # 2. Install all automation tools
  provisioner "shell" {
    script          = "scripts/provision-automation-toolbox.sh"
    execute_command = "sudo bash {{.Path}}"
  }

  # 3. Copy this repo's Ansible content into the image
  provisioner "file" {
    source      = "../ansible/"
    destination = "/opt/toolbox/ansible/"
  }

  # 4. Run server-baseline playbook locally to validate Ansible works
  provisioner "ansible" {
    playbook_file   = "../ansible/playbooks/server-baseline.yml"
    extra_arguments = [
      "--connection=local",
      "--limit=localhost",
      "-e", "ansible_python_interpreter=/usr/bin/python3"
    ]
  }

  # 5. Seal the image (removes SSH host keys, machine-id, cloud-init cache)
  provisioner "shell" {
    script          = "scripts/cleanup.sh"
    execute_command = "sudo bash {{.Path}}"
  }

  # 6. Write a manifest so CI can track what was produced and when
  post-processor "manifest" {
    output     = "packer-manifest-automation-toolbox.json"
    strip_path = true
  }
}
