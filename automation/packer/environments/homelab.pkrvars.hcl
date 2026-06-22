# =============================================================================
# environments/homelab.pkrvars.hcl
# =============================================================================
# Variable overrides for a home lab environment.
# Use with: packer build -var-file="environments/homelab.pkrvars.hcl" <template>.pkr.hcl
# =============================================================================

# Proxmox
proxmox_url          = "https://192.168.1.10:8006/api2/json"
proxmox_node         = "pve"
proxmox_storage_pool = "local-lvm"
proxmox_iso_storage  = "local"
proxmox_vm_id        = 9000

# VMware
vsphere_server     = "192.168.1.20"
vsphere_datacenter = "HomeLab"
vsphere_cluster    = "Cluster01"
vsphere_datastore  = "datastore1"
vsphere_network    = "VM Network"
vsphere_folder     = "Templates"

# VM sizing (smaller for home lab)
vm_cpu_count = 2
vm_memory_mb = 2048
vm_disk_gb   = 20

# Image name
image_name = "ubuntu-2404-homelab"
