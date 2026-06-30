# =============================================================================
# ubuntu-2604-gcp.pkr.hcl
# =============================================================================
# Builds a golden GCP custom image from the latest Ubuntu 26.04 LTS.
#
# How the googlecompute builder works:
#   1. Packer finds the latest Ubuntu 26.04 image in the ubuntu-os-cloud project
#   2. Creates a temporary GCE VM from it
#   3. Runs provisioners (shell + Ansible) over SSH
#   4. Stops the instance
#   5. Creates a custom image from the boot disk
#   6. Deletes the temporary instance and disk
#
# Prerequisites:
#   packer init .
#   gcloud auth application-default login
#   OR set GOOGLE_APPLICATION_CREDENTIALS to a service account JSON key
#
# Build:
#   packer build ubuntu-2604-gcp.pkr.hcl
#
# Build for a specific project:
#   packer build -var "gcp_project_id=my-project" ubuntu-2604-gcp.pkr.hcl
#
# Author  : IT-Architect-UK
# Repo    : https://github.com/IT-Architect-UK/monorepo
# =============================================================================

packer {
  required_version = ">= 1.10.0"

  required_plugins {
    googlecompute = {
      version = ">= 1.1.4"
      source  = "github.com/hashicorp/googlecompute"
    }
    ansible = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

locals {
  timestamp  = formatdate("YYYYMMDDHHmm", timestamp())    # GCP image names can't contain colons
  image_name = "${replace(var.image_name, "_", "-")}-${local.timestamp}"   # GCP names: lowercase, hyphens only
}

# ── Source: Google Compute Builder ───────────────────────────────────────────
source "googlecompute" "ubuntu-2604" {
  # ── GCP project and zone ──────────────────────────────────────────────────
  project_id = var.gcp_project_id
  zone       = var.gcp_zone

  # ── Build VM ──────────────────────────────────────────────────────────────
  machine_type = var.gcp_machine_type

  # Disk size for the build VM
  disk_size = var.vm_disk_gb
  disk_type = "pd-balanced"

  # ── Source image ──────────────────────────────────────────────────────────
  # Ubuntu 26.04 LTS from Google's managed image family
  # Using a family reference always picks the latest image automatically
  # This is the GCP equivalent of using most_recent = true in the AWS builder
  source_image_family  = "ubuntu-2604-lts-amd64"
  source_image_project_id = ["ubuntu-os-cloud"]    # Canonical's GCP project

  # ── SSH ────────────────────────────────────────────────────────────────────
  communicator = "ssh"
  ssh_username = "packer"
  ssh_timeout  = "15m"

  # Use OS Login for SSH (recommended GCP approach — no need to manage SSH keys manually)
  # Alternatively, set use_os_login = false and provide ssh_public_key
  use_os_login = false

  # ── Output image settings ─────────────────────────────────────────────────
  image_name        = local.image_name
  image_description = "${var.image_description} | Built: ${local.timestamp}"

  # Image family: allows "latest image in family" lookups
  # VMs launched with --image-family=golden-ubuntu-2604 always get the newest image
  image_family = "golden-ubuntu-2604"

  image_labels = {
    build-date  = formatdate("YYYY-MM-DD", timestamp())
    build-tool  = "packer"
    os          = "ubuntu-24-04-lts"
    purpose     = "golden-image"
  }

  # ── Metadata ──────────────────────────────────────────────────────────────
  # Enable OS Config agent for Patch Manager / VM Manager integration
  metadata = {
    enable-osconfig = "TRUE"
  }
}

# ── Build ─────────────────────────────────────────────────────────────────────
build {
  name    = "ubuntu-2604-gcp"
  sources = ["source.googlecompute.ubuntu-2604"]

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
      "HYPERVISOR=gcp",
      "COMPANY_NAME=${var.vm_company_name}",
    ]
  }

  provisioner "ansible" {
    playbook_file   = abspath("${path.root}/../../../ansible/playbooks/server-baseline.yml")
    user          = "packer"
    extra_arguments = [
      "--extra-vars", "ansible_python_interpreter=/usr/bin/python3",
      "--extra-vars", "target_hosts=default",
    ]
  }

  provisioner "shell" {
    script          = abspath("${path.root}/../../scripts/cleanup.sh")
    execute_command = "sudo bash '{{ .Path }}'"
  }

  post-processor "manifest" {
    output     = "packer-manifest.json"
    strip_path = true
  }
}
