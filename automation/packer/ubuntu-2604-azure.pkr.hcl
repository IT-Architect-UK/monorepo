# =============================================================================
# ubuntu-2604-azure.pkr.hcl
# =============================================================================
# Builds a golden Azure Managed Image from the latest Ubuntu 26.04 LTS.
#
# How the azure-arm builder works:
#   1. Packer creates a temporary resource group
#   2. Launches a build VM from the Canonical Ubuntu 26.04 marketplace image
#   3. Runs provisioners (shell + Ansible) over SSH
#   4. Runs waagent -deprovision (Azure's equivalent of Sysprep for Linux)
#   5. Deallocates and generalises the VM
#   6. Captures it as a Managed Image in your resource group
#   7. Deletes all temporary resources
#
# Prerequisites:
#   packer init .
#   az login  (or set ARM_CLIENT_ID + ARM_CLIENT_SECRET + ARM_TENANT_ID)
#   export PKR_VAR_azure_subscription_id="your-sub-id"
#
# Build:
#   packer build ubuntu-2604-azure.pkr.hcl
#
# Author  : IT-Architect-UK
# Repo    : https://github.com/IT-Architect-UK/monorepo
# =============================================================================

packer {
  required_version = ">= 1.10.0"

  required_plugins {
    azure = {
      version = ">= 2.1.0"
      source  = "github.com/hashicorp/azure"
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

# ── Source: Azure ARM Builder ─────────────────────────────────────────────────
source "azure-arm" "ubuntu-2604" {
  # ── Authentication ────────────────────────────────────────────────────────
  # Packer supports several auth methods (picks up Azure CLI session automatically)
  # For CI/CD, set: ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID env vars
  subscription_id = var.azure_subscription_id

  # ── Build VM settings ─────────────────────────────────────────────────────
  vm_size   = var.azure_vm_size
  location  = var.azure_location

  # Base image: latest Ubuntu 26.04 LTS from Canonical
  # image_sku is "server" (no Desktop environment)
  image_publisher = "Canonical"
  image_offer     = "ubuntu-24_04-lts"
  image_sku       = "server"
  image_version   = "latest"

  # ── SSH ────────────────────────────────────────────────────────────────────
  communicator = "ssh"
  ssh_username = "packer"
  ssh_timeout  = "20m"

  # ── Output: Managed Image ─────────────────────────────────────────────────
  managed_image_name                = local.image_name
  managed_image_resource_group_name = var.azure_resource_group

  # ── OS disk ────────────────────────────────────────────────────────────────
  os_type         = "Linux"
  os_disk_size_gb = var.vm_disk_gb

  # Tags applied to the resulting Managed Image
  azure_tags = {
    BuildDate  = formatdate("YYYY-MM-DD", timestamp())
    BuildTool  = "Packer"
    OS         = "Ubuntu-26.04-LTS"
    Purpose    = "GoldenImage"
    Repository = "https://github.com/IT-Architect-UK/monorepo"
  }
}

# ── Build ─────────────────────────────────────────────────────────────────────
build {
  name    = "ubuntu-2604-azure"
  sources = ["source.azure-arm.ubuntu-2604"]

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
      "HYPERVISOR=azure",
      "COMPANY_NAME=${var.vm_company_name}",
    ]
  }

  provisioner "ansible" {
    playbook_file = "../ansible/playbooks/server-baseline.yml"
    user          = "packer"
    extra_arguments = [
      "--extra-vars", "ansible_python_interpreter=/usr/bin/python3",
      "--extra-vars", "target_hosts=default",
    ]
  }

  provisioner "shell" {
    script          = "scripts/cleanup.sh"
    execute_command = "sudo bash '{{ .Path }}'"
  }

  # Azure-specific: deprovision the VM (equivalent to Linux Sysprep)
  # waagent removes: SSH host keys, cloud-init cache, provisioning logs
  # This MUST run last, and the VM cannot be used again after this step
  provisioner "shell" {
    inline = [
      "echo 'Deprovisioning Azure VM...'",
      "sudo /usr/sbin/waagent -force -deprovision+user",
      "echo 'Deprovisioning complete'"
    ]
  }

  post-processor "manifest" {
    output     = "packer-manifest.json"
    strip_path = true
  }
}
