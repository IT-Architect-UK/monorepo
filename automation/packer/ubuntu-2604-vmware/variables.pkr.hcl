# Variables for ubuntu-2604-vmware template

variable "image_name" {
  type    = string
  default = "ubuntu-2604-golden"
}

variable "image_description" {
  type    = string
  default = "Ubuntu 26.04 LTS golden image — built with Packer"
}

variable "ubuntu_iso_url" {
  type    = string
  default = "https://releases.ubuntu.com/resolute/ubuntu-26.04-live-server-amd64.iso"
}

variable "ubuntu_iso_checksum" {
  type    = string
  default = "sha256:e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433"
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

variable "vm_company_name" {
  type    = string
  default = "IT-Architect"
}
