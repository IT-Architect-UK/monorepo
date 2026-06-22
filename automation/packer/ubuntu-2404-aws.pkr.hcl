# =============================================================================
# ubuntu-2404-aws.pkr.hcl
# =============================================================================
# Builds a golden AWS AMI from the latest official Ubuntu 24.04 LTS image.
#
# How the amazon-ebs builder works:
#   1. Packer finds the latest Ubuntu 24.04 AMI published by Canonical
#   2. Launches a temporary EC2 instance from it
#   3. Runs provisioners (shell + Ansible) over SSH
#   4. Stops the instance and creates an AMI (EBS snapshot)
#   5. Terminates the source instance
#
# The result: an AMI in your account that you own and control.
# Every EC2 instance you launch from it starts pre-patched and pre-configured.
#
# Prerequisites:
#   packer init .
#   aws configure  (or set AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY env vars)
#
# Build:
#   packer build ubuntu-2404-aws.pkr.hcl
#
# Build for a specific region:
#   packer build -var "aws_region=us-east-1" ubuntu-2404-aws.pkr.hcl
#
# Copy AMI to multiple regions after build using the ami-copy post-processor.
#
# Author  : IT-Architect-UK
# Repo    : https://github.com/IT-Architect-UK/monorepo
# =============================================================================

packer {
  required_version = ">= 1.10.0"

  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
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

# ── Source: Amazon EBS Builder ────────────────────────────────────────────────
source "amazon-ebs" "ubuntu-2404" {
  # ── Region and instance ───────────────────────────────────────────────────
  region        = var.aws_region
  instance_type = var.aws_instance_type

  # Optional: place the build instance in a specific VPC/subnet
  # Leave empty to use the default VPC
  dynamic "vpc_filter" {
    for_each = var.aws_vpc_id != "" ? [var.aws_vpc_id] : []
    content {
      filters = {
        "vpc-id" = vpc_filter.value
      }
    }
  }

  # ── Find the latest official Ubuntu 24.04 AMI ─────────────────────────────
  # Canonical's AWS account ID: 099720109477
  # We use a filter to always get the newest Ubuntu 24.04 image automatically
  # This means the build is always based on the most recently published base image
  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
      state               = "available"
    }
    owners      = ["099720109477"]    # Canonical (Ubuntu publisher)
    most_recent = true
  }

  # ── SSH access ────────────────────────────────────────────────────────────
  # AWS Ubuntu AMIs use 'ubuntu' as the default user, not root
  communicator = "ssh"
  ssh_username = "ubuntu"
  ssh_timeout  = "15m"

  # Use a temporary SSH key pair — Packer creates and deletes it automatically
  temporary_key_pair_name = "packer-${local.timestamp}"

  # ── Security: IMDSv2 ──────────────────────────────────────────────────────
  # IMDSv2 requires a session token for metadata access — prevents SSRF attacks
  # This is AWS best practice and required by some compliance frameworks
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"    # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  # ── Output AMI settings ───────────────────────────────────────────────────
  ami_name        = local.image_name
  ami_description = "${var.image_description} | Built: ${local.timestamp}"

  # Tag the AMI and the snapshot it creates
  tags = {
    Name        = local.image_name
    BuildDate   = formatdate("YYYY-MM-DD", timestamp())
    BuildTool   = "Packer"
    OS          = "Ubuntu-24.04-LTS"
    Purpose     = "GoldenImage"
    Repository  = "https://github.com/IT-Architect-UK/monorepo"
  }

  # Tag the EC2 instance while it's being built
  run_tags = {
    Name    = "packer-build-${local.timestamp}"
    Purpose = "PackerBuild"
  }
}

# ── Build ─────────────────────────────────────────────────────────────────────
build {
  name    = "ubuntu-2404-aws"
  sources = ["source.amazon-ebs.ubuntu-2404"]

  provisioner "shell" {
    script          = "scripts/provision.sh"
    execute_command = "sudo bash '{{ .Path }}'"
  }

  provisioner "ansible" {
    playbook_file = "../../ansible/playbooks/server-baseline.yml"
    user          = "ubuntu"
    extra_arguments = [
      "--extra-vars", "ansible_python_interpreter=/usr/bin/python3",
      "--extra-vars", "target_hosts=default",
    ]
  }

  provisioner "shell" {
    script          = "scripts/cleanup.sh"
    execute_command = "sudo bash '{{ .Path }}'"
  }

  # Write out AMI ID and region to a manifest file for use in CI/CD pipelines
  post-processor "manifest" {
    output     = "packer-manifest.json"
    strip_path = true
  }
}
