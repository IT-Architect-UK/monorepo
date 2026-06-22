# =============================================================================
# Packer variable overrides — Ansible Control Node
#
# Use alongside homelab.pkrvars.hcl or production.pkrvars.hcl:
#
#   packer build \
#     -var-file="environments/homelab.pkrvars.hcl" \
#     -var-file="environments/ansible-server.pkrvars.hcl" \
#     ubuntu-2404-ansible-server-proxmox.pkr.hcl
#
# These values OVERRIDE the ones in homelab/production var files.
# =============================================================================

# Give the image a recognisable name (timestamp is appended automatically)
image_name        = "ansible-server"
image_description = "Ubuntu 24.04 Ansible Control Node — built by Packer"

# Ansible control nodes don't need much RAM. 2 GB is comfortable for up to
# ~50 managed hosts running playbooks in parallel (forks = 10).
vm_memory_mb = 2048
vm_cpu_count = 2
vm_disk_gb   = 20

# Use a dedicated VM ID to avoid collisions with other Packer builds
# Change this if 9001 is already in use in your Proxmox cluster
proxmox_vm_id = 9001
