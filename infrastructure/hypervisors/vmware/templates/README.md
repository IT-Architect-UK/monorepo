# VMware — Golden Template Creation

Scripts to prepare "golden" VM templates — fully-patched, sealed base images
that can be cloned in minutes to produce new servers.

## Scripts

| Script | Runs On | What It Does |
|--------|---------|-------------|
| `prepare-windows-2025-template.ps1` | Your workstation (PowerCLI) | Connects to vCenter, updates Windows, runs Sysprep, converts the VM to a template |
| `prepare-ubuntu-2404-template.sh` | Inside the Ubuntu VM | Updates Ubuntu, installs open-vm-tools, cleans unique identifiers, shuts down |

## Usage

```powershell
# Windows Server 2025
.\prepare-windows-2025-template.ps1 -vCenterServer "vcenter.lab.local" -VMName "ws2025-base"

# Ubuntu (run inside the VM)
sudo ./prepare-ubuntu-2404-template.sh
```

After the Ubuntu script shuts the VM down, right-click it in vCenter and choose **Convert to Template**.
