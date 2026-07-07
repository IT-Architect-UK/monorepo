# =============================================================================
# environments/production.pkrvars.hcl
# =============================================================================
# Variable overrides for a production environment.
# Passwords and secrets should be set via env vars, not in this file.
# =============================================================================

# AWS
aws_region        = "eu-west-2"
aws_instance_type = "t3.small"

# Azure
azure_resource_group = "rg-golden-images"
azure_location       = "uksouth"
azure_vm_size        = "Standard_B2s"

# GCP
gcp_project_id = "my-production-project"
gcp_zone       = "europe-west2-a"
gcp_machine_type = "e2-small"

# VM sizing (production-grade)
vm_cpu_count = 2
vm_memory_mb = 4096
vm_disk_gb   = 30

image_name        = "t-ubuntu-2604"
image_description = "Ubuntu 26.04 LTS — Production Golden Image — Built with Packer"
