# Variables for ubuntu-2604-automation-toolbox-proxmox template
# Full variable reference: ../environments/README.md

variable "image_name" {
  type    = string
  default = "ubuntu-2604-automation-toolbox"
}

variable "image_description" {
  type    = string
  default = "Ubuntu 26.04 Automation Toolbox — Ansible, Packer, Terraform, Docker, and more"
}

variable "ubuntu_iso_file" {
  type    = string
  default = ""
}

variable "cidata_iso_file" {
  type    = string
  default = "NFS-10GB-PROXMOX-1:iso/ubuntu-2604-cidata.iso"
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
