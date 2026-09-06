# Ubuntu 26.04 Golden Image — AWS AMI

Builds a hardened Ubuntu 26.04 LTS AMI in your own account from Canonical's latest official image, using the `amazon-ebs` builder. Every EC2 instance launched from it starts pre-patched, branded and baselined.

## How it works

1. Packer finds the newest Canonical AMI matching `ubuntu/images/hvm-ssd-gp3/ubuntu-resolute-26.04-amd64-server-*` (owner `099720109477`, `most_recent = true`)
2. Launches a temporary instance from it with a throw-away SSH key pair, IMDSv2 enforced (`http_tokens = "required"`, hop limit 1)
3. Uploads the helper scripts from `infrastructure/`, runs `../../scripts/provision.sh` (`HYPERVISOR=aws`), then the `server-baseline.yml` Ansible playbook, then `../../scripts/cleanup.sh`
4. Stops the instance, snapshots it into an AMI, terminates the instance

Unlike the Proxmox templates, the **Ansible provisioner runs on the build host** here, so Ansible must be installed alongside Packer.

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| Packer ≥ 1.10 | Plugins `amazon ~> 1.8` and `ansible ~> 1.1` (`packer init .`) |
| Ansible | On the build machine — the playbook is pushed over SSH from here |
| AWS credentials | Standard credential chain: `aws configure`, env vars or an instance profile. No `PKR_VAR_*` secrets are needed |

## Key variables (`variables.pkr.hcl`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `aws_region` | `eu-west-2` | Region to build and register the AMI in |
| `aws_instance_type` | `t3.micro` | Build instance type |
| `aws_vpc_id` | _(empty)_ | Build in a specific VPC (a `vpc_filter` is added only when set); empty = default VPC |
| `image_name` | `t-ubuntu-2604` | AMI name prefix (timestamp appended) |
| `image_description` | `Ubuntu 26.04 LTS golden image — built with Packer` | AMI description |
| `vm_company_name` | `IT-Architect` | Branding passed to `provision.sh` |

SSH user is `ubuntu` (Canonical's default), fixed in the template; there is no `ssh_password`.

## Build

```bash
cd automation/packer/builds/ubuntu-2604-aws
packer init .
packer build .                                    # defaults
packer build -var "aws_region=us-east-1" .        # another region
packer build -var-file="../../environments/production.pkrvars.hcl" .
```

## Output

An AMI named `t-ubuntu-2604-<YYYYMMDD-HHmm>`, tagged `Name`, `BuildDate`, `BuildTool`, `OS`, `Purpose` and `Repository`, plus `packer-manifest.json` in this directory recording the AMI ID and region for downstream pipelines. To publish the AMI in more regions, add `ami_regions` to the source block.
