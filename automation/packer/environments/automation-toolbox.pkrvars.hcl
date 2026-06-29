# =============================================================================
# environments/automation-toolbox.pkrvars.hcl
# =============================================================================
# Variable overrides specific to the Automation Toolbox image.
# Use alongside homelab.pkrvars.hcl:
#
#   packer build \
#     -var-file="environments/homelab.pkrvars.hcl" \
#     -var-file="environments/automation-toolbox.pkrvars.hcl" \
#     ubuntu-2604-automation-toolbox-proxmox.pkr.hcl
#
# Sensitive values must be set as environment variables:
#   export PKR_VAR_proxmox_password="your-root-password"
#   export PKR_VAR_ssh_password="your-chosen-packer-user-password"
# =============================================================================

image_name        = "automation-toolbox"
image_description = "Ubuntu 26.04 Automation Toolbox — Ansible, Packer, Terraform, AWS CLI, Azure CLI, kubectl, Helm, Docker, GitHub CLI"

# More resources than a standard VM — this host runs Packer builds and
# Terraform plans which are CPU/memory intensive
vm_cpu_count = 4
vm_memory_mb = 4096
vm_disk_gb   = 60    # Tools + Docker images + Terraform state need space

# Dedicated VM ID — change if 9002 is already in use in your Proxmox cluster
proxmox_vm_id = 9002
