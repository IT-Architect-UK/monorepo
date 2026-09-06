# Ubuntu 26.04 Golden Image — Azure Managed Image

Builds a hardened Ubuntu 26.04 LTS **Managed Image** in your subscription from Canonical's marketplace image, using the `azure-arm` builder.

## How it works

1. Packer creates a temporary resource group and a build VM from the Canonical marketplace image
2. Uploads the helper scripts from `infrastructure/`, runs `../../scripts/provision.sh` (`HYPERVISOR=azure`), then the `server-baseline.yml` Ansible playbook, then `../../scripts/cleanup.sh`
3. Runs `waagent -force -deprovision+user` — Azure's Linux equivalent of sysprep; the VM cannot be used again after this step
4. Deallocates and generalises the VM, captures it as a Managed Image in `azure_resource_group`, deletes the temporary resources

The **Ansible provisioner runs on the build host**, so Ansible must be installed alongside Packer.

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| Packer ≥ 1.10 | Plugins `azure ~> 2.6` and `ansible ~> 1.1` (`packer init .`) |
| Ansible | On the build machine |
| Azure session | `az login` (picked up automatically), or `ARM_CLIENT_ID` + `ARM_CLIENT_SECRET` + `ARM_TENANT_ID` for CI |
| `PKR_VAR_azure_subscription_id` | **Required** — the subscription to build in (marked sensitive) |

## Key variables (`variables.pkr.hcl`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `azure_subscription_id` | — | `PKR_VAR_azure_subscription_id` |
| `azure_resource_group` | `rg-packer-images` | Existing resource group that receives the Managed Image |
| `azure_location` | `uksouth` | Region |
| `azure_vm_size` | `Standard_B1s` | Build VM size |
| `vm_disk_gb` | `20` | OS disk size (`os_disk_size_gb`) |
| `image_name` | `t-ubuntu-2604` | Image name prefix (timestamp appended) |
| `vm_company_name` | `IT-Architect` | Branding passed to `provision.sh` |

SSH user is `packer`, fixed in the template; Packer generates the key pair.

## Build

```bash
cd automation/packer/builds/ubuntu-2604-azure
export PKR_VAR_azure_subscription_id="00000000-0000-0000-0000-000000000000"
az login
packer init .
packer build .
packer build -var-file="../../environments/production.pkrvars.hcl" .   # rg-golden-images, Standard_B2s
```

## Output

A Managed Image `t-ubuntu-2604-<YYYYMMDD-HHmm>` in `azure_resource_group`, tagged `BuildDate`, `BuildTool`, `OS`, `Purpose` and `Repository`, plus `packer-manifest.json` in this directory.

**Known issue:** the template's `image_offer` is still `ubuntu-24_04-lts`, so despite the name this build currently starts from Canonical's Ubuntu 24.04 marketplace image, not 26.04.
