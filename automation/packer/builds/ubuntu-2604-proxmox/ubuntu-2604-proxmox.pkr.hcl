# =============================================================================
# ubuntu-2604-proxmox.pkr.hcl
# =============================================================================
# Builds an Ubuntu 26.04 LTS template on Proxmox VE using Packer.
#
# What Packer does here:
#   1. Downloads the Ubuntu 26.04 ISO (or uses a cached copy)
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
#   packer build ubuntu-2604-proxmox.pkr.hcl
#
# Build with variable overrides:
#   packer build \
#     -var "proxmox_url=https://192.168.1.10:8006/api2/json" \
#     -var "proxmox_node=pve" \
#     -var "proxmox_vm_id=9001" \
#     ubuntu-2604-proxmox.pkr.hcl
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
  # Build a versioned image name: e.g. "t-ubuntu-2604-20240315"
  timestamp  = formatdate("YYYYMMDD-HHmm", timestamp())
  image_name = "${var.image_name}-${local.timestamp}"
}

# ── Source: Proxmox ISO Builder ───────────────────────────────────────────────
# This builder downloads an ISO, creates a VM, runs the installer automatically,
# then hands off to provisioners.
source "proxmox-iso" "ubuntu-2604" {
  # ── Proxmox connection ──────────────────────────────────────────────────
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password == "" ? null : var.proxmox_password
  token                    = var.proxmox_token == "" ? null : var.proxmox_token
  insecure_skip_tls_verify = true    # Set to false in production with valid cert
  node                     = var.proxmox_node

  # ── VM settings ─────────────────────────────────────────────────────────
  vm_id   = var.proxmox_vm_id
  vm_name = local.image_name

  # The ISO to boot from
  # Pre-uploaded ISO on Proxmox storage (set ubuntu_iso_file in homelab.pkrvars.hcl)
  # Run: pvesm list NFS-10GB-PROXMOX-1 --content iso
  iso_file         = var.ubuntu_iso_file
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
    model    = "virtio"
    bridge   = var.proxmox_network_bridge
    vlan_tag = var.proxmox_vlan_tag
  }

  # UEFI firmware — must accompany efi_config, otherwise Proxmox boots the
  # VM with SeaBIOS, which only tries the FIRST CD drive (the tiny cidata
  # disc) and dies with "Could not read from CDROM (code 0004)". Caught on
  # a real build of VM 9004.
  bios = "ovmf"

  # Cloud-init drive on the template: this is how every CLONE receives its
  # identity (hostname from the VM name, user/password/SSH key from the
  # provisioning playbook). Without it clones boot as anonymous copies —
  # caught live on the first built template.
  cloud_init              = true
  cloud_init_storage_pool = var.proxmox_storage_pool

  # EFI disk enables UEFI boot — recommended for Ubuntu 26.04
  efi_config {
    efi_storage_pool  = var.proxmox_storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = true
  }

  # ── Boot and autoinstall ─────────────────────────────────────────────────
  # Packer serves the http/ directory on a temporary HTTP server.
  # autoinstall user-data and meta-data are attached as a CD-ROM (cidata label)
  # The Ubuntu installer finds them automatically via cloud-init nocloud datasource.
  # No HTTP server needed — Packer can run from any machine with Proxmox API access.
  additional_iso_files {
    # ide3: keep the cidata disc AFTER the boot ISO in device order — on
    # ide0 it becomes the first CD the firmware tries to boot from.
    device           = "ide3"
    cd_files         = [abspath("${path.root}/../../http/user-data"), abspath("${path.root}/../../http/meta-data")]
    cd_label         = "cidata"
    iso_storage_pool = var.proxmox_iso_storage
    unmount          = true
  }

  boot_wait = "5s"
  boot_command = [
    "c",
    "linux /casper/vmlinuz autoinstall ds=nocloud ",
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
  name    = "ubuntu-2604-proxmox"
  sources = ["source.proxmox-iso.ubuntu-2604"]

  # Step 1: Shell provisioner — applies OS updates, tools, hardening
  # Upload helper scripts used by provision.sh
  provisioner "file" {
    sources = [
      abspath("${path.root}/../../../../infrastructure/servers/linux/configuration/apply-branding.sh"),
      abspath("${path.root}/../../../../infrastructure/servers/linux/configuration/disable-cloud-init.sh"),
      abspath("${path.root}/../../../../infrastructure/servers/linux/configuration/disable-ipv6.sh"),
      abspath("${path.root}/../../../../infrastructure/networking/firewall/setup-iptables.sh"),
      abspath("${path.root}/../../../../infrastructure/servers/linux/configuration/sync-monorepo.sh"),
    ]
    destination = "/tmp/"
  }

  provisioner "shell" {
    script          = abspath("${path.root}/../../scripts/provision.sh")
    execute_command = "sudo bash '{{ .Path }}'"
    environment_vars = [
      "HYPERVISOR=proxmox",
      "COMPANY_NAME=${var.vm_company_name}",
      "BUILD_PROFILE=golden",
    ]
  }

  # Step 2: Ansible server-baseline — runs INSIDE the guest against
  # localhost, so the machine running Packer needs NOTHING but Packer
  # (standalone principle: no hidden build-host dependencies). Ansible is
  # installed for the baseline run and removed again before sealing.
  provisioner "file" {
    source      = abspath("${path.root}/../../../ansible")
    destination = "/tmp/"
  }

  provisioner "shell" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "apt-get install -y ansible",
      "cd /tmp/ansible && ANSIBLE_ROLES_PATH=/tmp/ansible/roles ansible-playbook -i 'localhost,' -e '@inventory/group_vars/all.yml' playbooks/server-baseline.yml --connection=local --limit=localhost -e ansible_python_interpreter=/usr/bin/python3",
      "apt-get remove -y ansible && apt-get autoremove -y",
      "rm -rf /tmp/ansible",
    ]
    execute_command = "sudo bash {{.Path}}"
  }

  # Step 3: Cleanup — seal the image (remove machine-unique data)
  # This MUST be the last provisioner
  provisioner "shell" {
    script          = abspath("${path.root}/../../scripts/cleanup.sh")
    execute_command = "sudo bash '{{ .Path }}'"
  }

  # Post-processor: write a manifest of what was built
  post-processor "manifest" {
    output     = "packer-manifest.json"
    strip_path = true
  }
}
