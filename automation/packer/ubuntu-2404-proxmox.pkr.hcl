# =============================================================================
# ubuntu-2404-proxmox.pkr.hcl
# =============================================================================
# Builds an Ubuntu 24.04 LTS template on Proxmox VE using Packer.
#
# What Packer does here:
#   1. Downloads the Ubuntu 24.04 ISO (or uses a cached copy)
#   2. Creates a temporary VM on Proxmox using the proxmox-iso builder
#   3. Boots the VM and feeds a cloud-init autoinstall configuration
#      via a virtual CD-ROM (this replaces the manual installation wizard)
#   4. Waits for the OS to install and the VM to become reachable via SSH
#   5. Runs the shell provisioner (provision.sh) to apply updates & hardening
#   6. Runs the Ansible provisioner to apply our server-baseline role
#   7. Runs the cleanup provisioner (cleanup.sh) to seal the image
#   8. Converts the VM to a Proxmox template
#
# Cloud-init autoinstall (step 3) is Ubuntu's unattended installation system.
# It is configured via the http/user-data file in this directory.
# Think of it as the Linux equivalent of Windows Unattend.xml.
#
# Prerequisites:
#   packer init .                         ← download required plugins
#   export PKR_VAR_proxmox_password="..." ← set credentials via env var
#
# Build:
#   packer build ubuntu-2404-proxmox.pkr.hcl
#
# Build with variable overrides:
#   packer build \
#     -var "proxmox_url=https://192.168.1.10:8006/api2/json" \
#     -var "proxmox_node=pve" \
#     -var "proxmox_vm_id=9001" \
#     ubuntu-2404-proxmox.pkr.hcl
#
# Author  : IT-Architect-UK
# Repo    : https://github.com/IT-Architect-UK/monorepo
# =============================================================================

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

# Import shared variable definitions
# Variables are declared in variables.pkr.hcl — override them here or at build time

locals {
  # Build a versioned image name: e.g. "ubuntu-2404-golden-20240315"
  timestamp  = formatdate("YYYYMMDD-HHmm", timestamp())
  image_name = "${var.image_name}-${local.timestamp}"
}

# ── Source: Proxmox ISO Builder ───────────────────────────────────────────────
# This builder downloads an ISO, creates a VM, runs the installer automatically,
# then hands off to provisioners.
source "proxmox-iso" "ubuntu-2404" {
  # ── Proxmox connection ──────────────────────────────────────────────────
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  insecure_skip_tls_verify = true    # Set to false in production with valid cert
  node                     = var.proxmox_node

  # ── VM settings ─────────────────────────────────────────────────────────
  vm_id   = var.proxmox_vm_id
  vm_name = local.image_name

  # The ISO to boot from
  iso_url          = var.ubuntu_iso_url
  iso_checksum     = var.ubuntu_iso_checksum
  iso_storage_pool = var.proxmox_iso_storage

  # ── Hardware ─────────────────────────────────────────────────────────────
  cores  = var.vm_cpu_count
  memory = var.vm_memory_mb

  # Use SCSI controller — matches what we use in our deployment scripts
  scsi_controller = "virtio-scsi-single"

  disks {
    disk_size    = "${var.vm_disk_gb}G"
    storage_pool = var.proxmox_storage_pool
    type         = "scsi"
  }

  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }

  # EFI disk enables UEFI boot — recommended for Ubuntu 24.04
  efi_config {
    efi_storage_pool  = var.proxmox_storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = true
  }

  # ── Boot and autoinstall ─────────────────────────────────────────────────
  # Packer serves the http/ directory on a temporary HTTP server.
  # The boot_command types into the VM's console to tell the Ubuntu installer
  # to fetch its configuration from that HTTP server automatically.
  http_directory = "http"

  boot_wait = "5s"
  boot_command = [
    "c",                                                            # Enter GRUB command line
    "linux /casper/vmlinuz ",                                       # Kernel
    "autoinstall ",                                                 # Enable unattended install
    "ds='nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/' ",   # cloud-init server URL
    "--- <enter>",
    "initrd /casper/initrd <enter>",
    "boot <enter>"
  ]

  # ── SSH access for provisioning ──────────────────────────────────────────
  # Packer uses SSH to run provisioners after the OS installs
  communicator     = "ssh"
  ssh_username     = var.ssh_username
  ssh_password     = var.ssh_password
  ssh_timeout      = "30m"    # Ubuntu installation can take 10-20 minutes

  # ── Template settings ────────────────────────────────────────────────────
  # After provisioning, Packer converts the VM to a template
  template_name        = local.image_name
  template_description = "${var.image_description}\nBuilt: ${local.timestamp}"
  onboot               = false   # Templates should not auto-start
  qemu_agent           = true    # Enable QEMU guest agent socket
}

# ── Build ─────────────────────────────────────────────────────────────────────
build {
  name    = "ubuntu-2404-proxmox"
  sources = ["source.proxmox-iso.ubuntu-2404"]

  # Step 1: Shell provisioner — applies OS updates, tools, hardening
  # Upload helper scripts used by provision.sh
  provisioner "file" {
    sources = [
      "${path.root}/../../infrastructure/servers/linux/configuration/apply-branding.sh",
      "${path.root}/../../infrastructure/servers/linux/configuration/disable-cloud-init.sh",
      "${path.root}/../../infrastructure/servers/linux/configuration/disable-ipv6.sh",
      "${path.root}/../../infrastructure/networking/firewall/setup-iptables.sh",
    ]
    destination = "/tmp/"
  }

  provisioner "shell" {
    script          = "scripts/provision.sh"
    execute_command = "sudo bash '{{ .Path }}'"
    environment_vars = [
      "HYPERVISOR=proxmox",
      "COMPANY_NAME=${var.vm_company_name}",
    ]
  }

  # Step 2: Ansible provisioner — applies our server-baseline role
  # Requires Ansible installed on the machine running Packer (not the build VM)
  provisioner "ansible" {
    playbook_file = "../ansible/playbooks/server-baseline.yml"
    user          = var.ssh_username
    extra_arguments = [
      "--extra-vars", "ansible_python_interpreter=/usr/bin/python3",
      "--extra-vars", "target_hosts=default",
      "-v"
    ]
  }

  # Step 3: Cleanup — seal the image (remove machine-unique data)
  # This MUST be the last provisioner
  provisioner "shell" {
    script          = "scripts/cleanup.sh"
    execute_command = "sudo bash '{{ .Path }}'"
  }

  # Post-processor: write a manifest of what was built
  post-processor "manifest" {
    output     = "packer-manifest.json"
    strip_path = true
  }
}
