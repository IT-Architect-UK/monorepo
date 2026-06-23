# =============================================================================
# environments/homelab.pkrvars.hcl
# =============================================================================
# Variable overrides for a home lab environment.
# Use with: packer build -var-file="environments/homelab.pkrvars.hcl" <template>.pkr.hcl
#
# Sensitive values (passwords) must be set as environment variables:
#   export PKR_VAR_proxmox_password="your-password"
#   export PKR_VAR_ssh_password="your-packer-user-password"
# =============================================================================

# ── Proxmox ──────────────────────────────────────────────────────────────────
proxmox_url          = "https://posvmpws01.skint.private:8006/api2/json"
proxmox_node         = "POSVMPWS01"
proxmox_username     = "root@pam"
proxmox_storage_pool = "NFS-10GB-PROXMOX-1"
proxmox_iso_storage  = "NFS-10GB-PROXMOX-1"
proxmox_vm_id        = 106

# ── VMware (fill in when ready to test VMware) ───────────────────────────────
vsphere_server     = "192.168.1.20"
vsphere_datacenter = "HomeLab"
vsphere_cluster    = "Cluster01"
vsphere_datastore  = "datastore1"
vsphere_network    = "VM Network"
vsphere_folder     = "Templates"

# ── VM sizing ─────────────────────────────────────────────────────────────────
vm_cpu_count = 2
vm_memory_mb = 2048
vm_disk_gb   = 20

# ── Image name ────────────────────────────────────────────────────────────────
image_name = "ubuntu-2404-homelab"
