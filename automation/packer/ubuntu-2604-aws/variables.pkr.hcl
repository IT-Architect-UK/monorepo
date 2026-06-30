# Variables for ubuntu-2604-aws template

variable "image_name" {
  type    = string
  default = "ubuntu-2604-golden"
}

variable "image_description" {
  type    = string
  default = "Ubuntu 26.04 LTS golden image — built with Packer"
}

variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "aws_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "aws_vpc_id" {
  type    = string
  default = ""
}

variable "vm_company_name" {
  type    = string
  default = "IT-Architect"
}
