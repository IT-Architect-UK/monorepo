# Cloud

Account-level cloud platform automation: baseline hardening, networking, compute tooling, and identity. (VM *image* builds live in `automation/packer/`; cloud monitoring agents in `monitoring/cloud/`; cloud backup in `backup/cloud/`.)

## AWS

| Script | Purpose |
|--------|---------|
| `aws/account/aws-account-baseline.sh` | Security baseline for a new account: CloudTrail, GuardDuty, IAM password policy, S3 public-access block |
| `aws/networking/deploy-vpc.sh` | Production-ready VPC: public/private subnets across 2 AZs, IGW, NAT, route tables |
| `aws/compute/aws-ec2-inventory.py` | EC2 inventory across regions → table + CSV (requires `boto3`) |
| `aws/compute/install-cloudwatch-agent-ubuntu.sh` | CloudWatch unified agent on Ubuntu (system metrics + logs) |

Prerequisites: AWS CLI v2 configured (`aws configure`) with sufficient IAM permissions. Each script's header lists the exact permissions and variables.

## Azure

| Script | Purpose |
|--------|---------|
| `azure/identity/convert-all-onprem-users-to-cloud.ps1` | Convert **all** AD-synchronised users to cloud-only (Entra ID) |
| `azure/identity/convert-specific-onprem-users-to-cloud.ps1` | Convert a named list of users to cloud-only |

Prerequisites: PowerShell with the MSOnline module (installed automatically), Global Admin rights. **Both scripts change identity sourcing — read the script header and test on a single account first.**

## GCP

Placeholder directories (`account/`, `compute/`, `networking/`) — GCP coverage currently lives in `monitoring/cloud/gcp/` and `image-maintenance/cloud/gcp/`.
