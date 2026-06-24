# =============================================================================
# ubuntu-2404-vmware.pkr.hcl
# =============================================================================
# Builds an Ubuntu 24.04 LTS template on VMware vSphere using Packer.
#
# Uses the vsphere-iso builder, which connects to vCenter via its API —
# no need for SSH access to the ESXi host itself.
#
# Prerequisites:
#   packer init .
#   export PKR_VAR_vsphere_password="..."
#
# Build:
#   packer build ubuntu-2404-vmware.pkr.hcl
#
# Build for a specific environment:
#   packer build \
#     -var-file="environments/homelab.pkrvars.hcl" \
#     ubuntu-2404-vmware.pkr.hcl
#
# Author  : IT-Architect-UK
# Repo    : https://github.com/IT-Architect-UK/monorepo
# =============================================================================

packer {
  required_version = ">= 1.10.0"

  required_plugins {
    vsphere = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/vsphere"
    }
    ansible = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

locals {
  timestamp  = formatdate("YYYYMMDD-HHmm", timestamp())
  image_name = "${var.image_name}-${local.timestamp}"
}

# ── Source: vSphere ISO Builder ───────────────────────────────────────────────
source "vsphere-iso" "ubuntu-2404" {
  # ── vCenter connection ──────────────────────────────────────────────────
  vcenter_server      = var.vsphere_server
  username            = var.vsphere_username
  password            = var.vsphere_password
  insecure_connection = true    # Set to false with a valid TLS cert

  # ── Placement ────────────────────────────────────────────────────────────
  datacenter = var.vsphere_datacenter
  cluster    = var.vsphere_cluster
  datastore  = var.vsphere_datastore
  folder     = var.vsphere_folder
  vm_name    = local.image_name

  # ── Hardware ─────────────────────────────────────────────────────────────
  guest_os_type = "ubuntu64Guest"
  CPUs          = var.vm_cpu_count
  RAM           = var.vm_memory_mb
  firmware      = "efi"    # UEFI boot

  disk_controller_type = ["pvscsi"]
  storage {
    disk_size             = var.vm_disk_gb * 1024    # vsphere takes MB
    disk_thin_provisioned = true
  }

  network_adapters {
    network      = var.vsphere_network
    network_card = "vmxnet3"
  }

  # CD-ROM for the ISO
  iso_url      = var.ubuntu_iso_url
  iso_checksum = var.ubuntu_iso_checksum

  # ── Autoinstall via CD-ROM ────────────────────────────────────────────────
  # For VMware, we serve autoinstall config via an extra CD-ROM image (iso)
  # rather than an HTTP server. This works in environments without internet.
  # The cd_files list gets bundled into a temporary ISO.
  cd_files = [
    "http/user-data",
    "http/meta-data"
  ]
  cd_label = "cidata"

  # ── Boot command ──────────────────────────────────────────────────────────
  boot_wait = "5s"
  boot_command = [
    "c",
    "linux /casper/vmlinuz ",
    "autoinstall ",
    "ds=nocloud;seedfrom=/dev/sr1/ ",    # sr1 = second CD-ROM (our cidata ISO)
    "--- <enter>",
    "initrd /casper/initrd <enter>",
    "boot <enter>"
  ]

  # ── SSH ───────────────────────────────────────────────────────────────────
  communicator = "ssh"
  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "40m"

  # ── Template conversion ───────────────────────────────────────────────────
  # After provisioning, Packer converts the VM to a vSphere template
  convert_to_template = true

  # VM notes visible in vCenter
  notes = "${var.image_description}\nBuilt by Packer: ${local.timestamp}"
}

# ── Build ─────────────────────────────────────────────────────────────────────
build {
  name    = "ubuntu-2404-vmware"
  sources = ["source.vsphere-iso.ubuntu-2404"]

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
    execute_command = "sudo bash '{{ .Path }}'"
    environment_vars = [
      "HYPERVISOR=vmware",
      "COMPANY_NAME=${var.vm_company_name}",
    ]
  }

  provisioner "ansible" {
    playbook_file = "../ansible/playbooks/server-baseline.yml"
    user          = var.ssh_username
    extra_arguments = [
      "--extra-vars", "ansible_python_interpreter=/usr/bin/python3",
      "--extra-vars", "target_hosts=default",
    ]
  }

  provisioner "shell" {
    script          = "scripts/cleanup.sh"
    execute_command = "sudo bash '{{ .Path }}'"
  }

  post-processor "manifest" {
    output     = "packer-manifest.json"
    strip_path = true
  }
}
