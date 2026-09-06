# Ubuntu 26.04 Golden Image — GCP Custom Image

Builds a hardened Ubuntu 26.04 LTS custom image in your project from Google's `ubuntu-2604-lts-amd64` image family, using the `googlecompute` builder.

## How it works

1. Packer picks the newest image in family `ubuntu-2604-lts-amd64` (project `ubuntu-os-cloud`) and creates a temporary VM from it
2. Uploads the helper scripts from `infrastructure/`, runs `../../scripts/provision.sh` (`HYPERVISOR=gcp`), then the `server-baseline.yml` Ansible playbook, then `../../scripts/cleanup.sh`
3. Stops the VM, creates a custom image from its boot disk, deletes the VM and disk

The **Ansible provisioner runs on the build host**, so Ansible must be installed alongside Packer. OS Login is off (`use_os_login = false`); Packer manages a temporary SSH key for the `packer` user. The image is created with `enable-osconfig = TRUE` metadata for VM Manager / Patch integration.

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| Packer ≥ 1.10 | Plugins `googlecompute ~> 1.2` and `ansible ~> 1.1` (`packer init .`) |
| Ansible | On the build machine |
| GCP credentials | `gcloud auth application-default login`, or `GOOGLE_APPLICATION_CREDENTIALS` pointing at a service-account key |
| `gcp_project_id` | **Required** — empty by default; pass with `-var` or a var file |

## Key variables (`variables.pkr.hcl`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `gcp_project_id` | _(empty)_ | Project to build in |
| `gcp_zone` | `europe-west2-a` | Zone for the build VM |
| `gcp_machine_type` | `e2-micro` | Build machine type |
| `vm_disk_gb` | `20` | Boot disk size (`pd-balanced`) |
| `image_name` | `t-ubuntu-2604` | Image name prefix — underscores become hyphens, timestamp `YYYYMMDDHHmm` appended (GCP names allow no colons) |
| `image_description` | `Ubuntu 26.04 LTS golden image — built with Packer` | Image description |
| `vm_company_name` | `IT-Architect` | Branding passed to `provision.sh` |

## Build

```bash
cd automation/packer/builds/ubuntu-2604-gcp
gcloud auth application-default login
packer init .
packer build -var "gcp_project_id=my-project" .
packer build -var-file="../../environments/production.pkrvars.hcl" .   # sets project, zone, e2-small
```

## Output

A custom image `t-ubuntu-2604-<YYYYMMDDHHmm>` in image family **`golden-ubuntu-2604`** — launch with `--image-family=golden-ubuntu-2604` to always get the newest build — labelled `build-date`, `build-tool`, `os` and `purpose`, plus `packer-manifest.json` in this directory.

**Known issue:** the `os` image label is still `ubuntu-24-04-lts`; the source family and image name are 26.04.
