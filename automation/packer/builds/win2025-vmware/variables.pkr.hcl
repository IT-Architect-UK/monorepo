# Variables for win2025-vmware template

variable "image_name" {
  type    = string
  default = "t-win2025"
}

variable "winrm_username" {
  type    = string
  default = "packer"
}

variable "winrm_password" {
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
  default = 4096
}

variable "vm_disk_gb" {
  type    = number
  default = 50
}

variable "vsphere_server" {
  type    = string
  default = "vcenter.lab.local"
}

variable "vsphere_username" {
  type    = string
  default = "administrator@vsphere.local"
}

variable "vsphere_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "vsphere_datacenter" {
  type    = string
  default = "Datacenter"
}

variable "vsphere_cluster" {
  type    = string
  default = "Cluster01"
}

variable "vsphere_datastore" {
  type    = string
  default = "datastore1"
}

variable "vsphere_network" {
  type    = string
  default = "VM Network"
}

variable "vsphere_folder" {
  type    = string
  default = "Templates"
}
