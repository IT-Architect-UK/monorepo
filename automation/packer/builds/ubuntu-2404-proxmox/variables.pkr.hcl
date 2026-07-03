# Variables for ubuntu-2404-proxmox template

variable "image_name" {
  type    = string
  default = "ubuntu-2404-golden"
}

variable "image_description" {
  type    = string
  default = "Ubuntu 24.04 LTS golden image — built with Packer"
}

variable "ubuntu_iso_file" {
  type    = string
  default = ""
}

variable "ssh_username" {
  type    = string
  default = "packer"
}

variable "ssh_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "vm_cpu_count" {
  type    = number
  default = 2
}

variable "vm_memory_mb" {
  type    = number
  default = 2048
}

variable "vm_disk_gb" {
  type    = number
  default = 20
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

variable "proxmox_token" {
  # API token secret — used with proxmox_username "user@realm!tokenid".
  # Leave empty to authenticate with proxmox_password instead.
  type      = string
  default   = ""
  sensitive = true
}

variable "proxmox_vm_id" {
  type    = number
  default = 9004
}

variable "vm_company_name" {
  type    = string
  default = "IT-Architect"
}

variable "proxmox_network_bridge" {
  type    = string
  default = "VLANs"
}

variable "proxmox_vlan_tag" {
  type    = string
  default = "4"
}

# ─── Unused elsewhere ──────────────────────────────────────────────────────────
# environments/homelab.pkrvars.hcl is a shared file covering every hypervisor
# (Proxmox, VMware, Windows) by design. This template is Proxmox+Ubuntu only,
# so it doesn't use these — declared here purely so packer validate/build
# stop warning "was set but was not declared as an input variable" for them.
variable "vsphere_server" {
  type    = string
  default = null
}

variable "vsphere_datacenter" {
  type    = string
  default = null
}

variable "vsphere_cluster" {
  type    = string
  default = null
}

variable "vsphere_datastore" {
  type    = string
  default = null
}

variable "vsphere_network" {
  type    = string
  default = null
}

variable "vsphere_folder" {
  type    = string
  default = null
}

variable "win_iso_file" {
  type    = string
  default = null
}

variable "virtio_iso_file" {
  type    = string
  default = null
}
