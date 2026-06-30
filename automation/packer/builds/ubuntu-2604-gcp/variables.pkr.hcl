# Variables for ubuntu-2604-gcp template

variable "image_name" {
  type    = string
  default = "ubuntu-2604-golden"
}

variable "image_description" {
  type    = string
  default = "Ubuntu 26.04 LTS golden image — built with Packer"
}

variable "gcp_project_id" {
  type    = string
  default = ""
}

variable "gcp_zone" {
  type    = string
  default = "europe-west2-a"
}

variable "gcp_machine_type" {
  type    = string
  default = "e2-micro"
}

variable "vm_disk_gb" {
  type    = number
  default = 20
}

variable "vm_company_name" {
  type    = string
  default = "IT-Architect"
}
