###############################################################################
# Packer Template: Ubuntu 26.04 Automation Toolbox — Proxmox
#
# PURPOSE
#   Builds a Proxmox VM template ready to use as a centralised automation
#   management host. On first boot the VM has:
#     • Ansible, Packer, Terraform, AWS CLI v2, Azure CLI
#     • kubectl, Helm, GitHub CLI, Docker CE
#     • Python 3 with boto3, azure-identity, google-cloud
#     • jq, yq
#
# USAGE (single-file — self-contained, no variables.pkr.hcl needed)
#   packer init ubuntu-2604-automation-toolbox-proxmox.pkr.hcl
#   packer build \
#     -var-file="environments/homelab.pkrvars.hcl" \
#     -var-file="environments/automation-toolbox.pkrvars.hcl" \
#     ubuntu-2604-automation-toolbox-proxmox.pkr.hcl
###############################################################################

packer {
  required_version = ">= 1.10.0"
  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# ─── Variables (self-contained — not loaded from variables.pkr.hcl) ──────────

variable "image_name" {
  type    = string
  default = "POSLXPDEPLOY01"
}

variable "image_description" {
  type    = string
  default = "Ubuntu 26.04 LTS Automation Toolbox — built with Packer"
}

variable "ubuntu_iso_file" {
  type    = string
  default = ""
}

variable "ubuntu_iso_url" {
  type    = string
  default = "https://releases.ubuntu.com/resolute/ubuntu-26.04-live-server-amd64.iso"
}

variable "ubuntu_iso_checksum" {
  type    = string
  default = "sha256:e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433"
}

variable "ssh_username" {
  type    = string
  default = "packer"
}

variable "ssh_password" {
  type      = string
  default   = "packer-temp-password"
  sensitive = true
}

variable "vm_cpu_count" {
  type    = number
  default = 4
}

variable "vm_memory_mb" {
  type    = number
  default = 4096
}

variable "vm_disk_gb" {
  type    = number
  default = 60
}

variable "proxmox_url" {
  type    = string
  default = "https://192.168.1.10:8006/api2/json"
}

variable "proxmox_username" {
  type    = string
  default = "root@pam"
}

variable "proxmox_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "proxmox_node" {
  type    = string
  default = "pve"
}

variable "proxmox_storage_pool" {
  type    = string
  default = "local-lvm"
}

variable "proxmox_iso_storage" {
  type    = string
  default = "local"
}

variable "cidata_iso_file" {
  type        = string
  default     = "NFS-10GB-PROXMOX-1:iso/ubuntu-2604-cidata.iso"
  description = "Path to the pre-built cloud-init cidata ISO on Proxmox storage"
}

variable "proxmox_vm_id" {
  type    = number
  default = 9002
}

variable "vm_company_name" {
  type    = string
  default = "IT-Architect"
}

variable "semaphore_admin_password" {
  type      = string
  default   = ""
  sensitive = true
}

# ─── Locals ───────────────────────────────────────────────────────────────────
locals {
  timestamp  = formatdate("YYYYMMDD-HHmm", timestamp())
  image_name = "${var.image_name}-${local.timestamp}"
}

# ─── Source ───────────────────────────────────────────────────────────────────
source "proxmox-iso" "automation-toolbox" {

  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  vm_id                = var.proxmox_vm_id
  vm_name              = local.image_name
  template_name        = local.image_name
  template_description = "Ubuntu 26.04 Automation Toolbox | Built ${local.timestamp} by Packer | Tools: Ansible, Packer, Terraform, AWS CLI, Azure CLI, kubectl, Helm, Docker, GitHub CLI"

  boot_iso {
    iso_file         = var.ubuntu_iso_file
    iso_storage_pool = var.proxmox_iso_storage
    unmount          = true
  }

  cores           = var.vm_cpu_count
  memory          = var.vm_memory_mb
  os              = "l26"
  qemu_agent      = true
  scsi_controller = "virtio-scsi-single"

  disks {
    disk_size    = "${var.vm_disk_gb}G"
    format       = "raw"
    storage_pool = var.proxmox_storage_pool
    type         = "virtio"
  }

  network_adapters {
    bridge   = "VLANs"
    model    = "virtio"
    firewall = false
    vlan_tag = "4"
  }

  efi_config {
    efi_storage_pool  = var.proxmox_storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = true
  }
  bios = "ovmf"

  additional_iso_files {
    iso_file = var.cidata_iso_file
    unmount  = true
  }

  boot_command = [
    "<wait3>",
    "c<wait>",
    "linux /casper/vmlinuz nomodeset --- autoinstall ds=nocloud<wait>",
    "<enter><wait>",
    "initrd /casper/initrd<wait>",
    "<enter><wait>",
    "boot<enter>"
  ]
  boot_wait = "5s"

  communicator           = "ssh"
  ssh_username           = var.ssh_username
  ssh_password           = var.ssh_password
  ssh_timeout            = "90m"
  ssh_handshake_attempts = 50
}

# ─── Build ────────────────────────────────────────────────────────────────────
build {
  name    = "automation-toolbox"
  sources = ["source.proxmox-iso.automation-toolbox"]

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

  provisioner "shell" {
    script          = "scripts/provision-automation-toolbox.sh"
    execute_command = "sudo bash {{.Path}}"
  }

  provisioner "shell" {
    inline          = ["chown -R packer:packer /opt/toolbox"]
    execute_command = "sudo bash -c '{{.Path}}'"
  }

  provisioner "file" {
    source      = "../ansible/"
    destination = "/opt/toolbox/ansible/"
  }

  # Run server-baseline playbook inside the VM (Ansible is installed by provision-automation-toolbox.sh)
  provisioner "shell" {
    inline = [
      "cd /opt/toolbox/ansible && ansible-playbook playbooks/server-baseline.yml --connection=local --limit=localhost -e ansible_python_interpreter=/usr/bin/python3"
    ]
    execute_command = "sudo bash -c '{{.Path}}'"
  }

  provisioner "shell" {
    script          = "scripts/cleanup.sh"
    execute_command = "sudo bash {{.Path}}"
  }

  post-processor "manifest" {
    output     = "packer-manifest-automation-toolbox.json"
    strip_path = true
  }
}
