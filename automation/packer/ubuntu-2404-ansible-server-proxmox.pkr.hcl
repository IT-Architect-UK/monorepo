###############################################################################
# Packer Template: Ubuntu 24.04 Ansible Control Node — Proxmox
#
# PURPOSE
#   Builds a Proxmox VM template that is ready to use as an Ansible control
#   node. On first boot the VM has:
#     • Ansible (latest from the official PPA)
#     • All playbooks and roles from this repo copied to /opt/ansible/
#     • SSH agent socket configured for key forwarding to managed hosts
#     • A dedicated 'ansible' service account
#     • Python 3, sshpass, and common Ansible Galaxy collections pre-installed
#
# USAGE
#   packer init .
#   packer validate -var-file="environments/homelab.pkrvars.hcl" \
#                   -var-file="environments/ansible-server.pkrvars.hcl" \
#                   ubuntu-2404-ansible-server-proxmox.pkr.hcl
#
#   packer build  -var-file="environments/homelab.pkrvars.hcl" \
#                 -var-file="environments/ansible-server.pkrvars.hcl" \
#                 ubuntu-2404-ansible-server-proxmox.pkr.hcl
#
# WHAT HAPPENS NEXT
#   1. Packer creates a Proxmox template called "ansible-server-<timestamp>"
#   2. Clone the template to create your Ansible control node VM
#   3. SSH in and run: sudo /opt/ansible/bootstrap-control-node.sh
#   4. Use the VM to run playbooks against your other servers
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
  image_name = "ansible-server-${local.timestamp}"
}

# ─── Variables (merge with environments/*.pkrvars.hcl) ────────────────────────
# All variables are declared in variables.pkr.hcl.
# Ansible-server–specific overrides live in environments/ansible-server.pkrvars.hcl.

# ─── Source: Proxmox ISO ──────────────────────────────────────────────────────
source "proxmox-iso" "ansible-server" {

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
  template_description = "Ubuntu 24.04 Ansible Control Node | Built ${local.timestamp} by Packer"

  # ── ISO source ──────────────────────────────────────────────────────────────
  iso_url          = var.ubuntu_iso_url
  iso_checksum     = var.ubuntu_iso_checksum
  iso_storage_pool = var.proxmox_iso_storage
  unmount_iso      = true

  # ── VM hardware ─────────────────────────────────────────────────────────────
  # Ansible control node: 2 vCPU / 2 GB RAM is comfortable for up to ~50 managed hosts
  cores   = var.vm_cpu_count
  memory  = var.vm_memory_mb
  os      = "l26"
  qemu_agent = true
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
  # boot_command below handles EFI boot order via GRUB command line
  bios         = "ovmf"

  # ── Autoinstall (Ubuntu unattended install) ──────────────────────────────────
  http_directory   = "http"
  http_bind_address = "0.0.0.0"
  http_port_min    = 8802
  http_port_max    = 8802

  # The boot command focuses the VM console then sends keystrokes to tell the
  # Ubuntu installer to use autoinstall from our HTTP server.
  boot_command = [
    "<wait3>",
    "c<wait>",
    "linux /casper/vmlinuz --- autoinstall ds=nocloud-net;seedfrom=http://{{ .HTTPIP }}:{{ .HTTPPort }}/<wait>",
    "<enter><wait>",
    "initrd /casper/initrd<wait>",
    "<enter><wait>",
    "boot<enter>"
  ]
  boot_wait = "5s"

  # ── SSH (Packer communicator) ────────────────────────────────────────────────
  communicator = "ssh"
  # Credentials match what user-data creates for the packer user
  ssh_username         = var.ssh_username
  ssh_password         = var.ssh_password
  ssh_timeout          = "30m"
  ssh_handshake_attempts = 50

  # ── Convert to template on success ──────────────────────────────────────────
  # Packer converts the VM to a Proxmox template automatically after provisioning.
}

# ─── Build ────────────────────────────────────────────────────────────────────
build {
  name    = "ansible-server"
  sources = ["source.proxmox-iso.ansible-server"]

  # 1. Base OS hardening (same as every other image: UFW, fail2ban, SSH hardening)
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
    execute_command = "sudo bash {{.Path}}"
    pause_before    = "10s"
    environment_vars = [
      "HYPERVISOR=proxmox",
      "COMPANY_NAME=${var.vm_company_name}",
    ]
  }

  # 2. Install Ansible + dependencies (Ansible-server–specific)
  provisioner "shell" {
    script          = "scripts/provision-ansible-server.sh"
    execute_command = "sudo bash {{.Path}}"
  }

  # 3. Copy this repo's Ansible content into the image at /opt/ansible/
  #    Engineers clone once; the control node always ships with the latest playbooks.
  provisioner "file" {
    source      = "../ansible/"      # relative to this .pkr.hcl file
    destination = "/opt/ansible/"
  }

  # 4. Run server-baseline playbook LOCALLY (control node configuring itself)
  #    This validates that Ansible works and applies the same baseline as
  #    every other server — we eat our own cooking.
  provisioner "ansible" {
    playbook_file   = "../ansible/playbooks/server-baseline.yml"
    extra_arguments = [
      "--connection=local",
      "--limit=localhost",
      "-e", "ansible_python_interpreter=/usr/bin/python3"
    ]
  }

  # 5. Image sealing — removes SSH host keys, cloud-init cache, machine-id etc.
  provisioner "shell" {
    script          = "scripts/cleanup.sh"
    execute_command = "sudo bash {{.Path}}"
  }

  # 6. Write a manifest so CI can track which image was produced and when
  post-processor "manifest" {
    output     = "packer-manifest-ansible-server.json"
    strip_path = true
  }
}
