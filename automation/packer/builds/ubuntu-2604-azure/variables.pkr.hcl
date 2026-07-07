# Variables for ubuntu-2604-azure template

variable "image_name" {
  type    = string
  default = "t-ubuntu-2604"
}

variable "azure_subscription_id" {
  type      = string
  default   = ""
  sensitive = true
}

variable "azure_resource_group" {
  type    = string
  default = "rg-packer-images"
}

variable "azure_location" {
  type    = string
  default = "uksouth"
}

variable "azure_vm_size" {
  type    = string
  default = "Standard_B1s"
}

variable "vm_disk_gb" {
  type    = number
  default = 20
}

variable "vm_company_name" {
  type    = string
  default = "IT-Architect"
}
