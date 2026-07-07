# VMware — VM Provisioning from Templates

Scripts to deploy new VMs by cloning existing templates.

## Scripts

| Script | What It Does |
|--------|-------------|
| `clone-from-template.ps1` | Clones a single template to a new VM with optional hardware overrides |
| `deploy-vm-from-template.ps1` | Reads a CSV and deploys multiple VMs in one operation |

## Quick Reference

```powershell
# Single VM
.\clone-from-template.ps1 -vCenterServer "vcenter.lab.local" `
    -TemplateName "t-ubuntu-2404" -VMName "web01" -PowerOn

# Bulk (CSV)
.\deploy-vm-from-template.ps1 -vCenterServer "vcenter.lab.local" -CsvPath ".\vms.csv"
```

## CSV Format

```csv
Name,Template,Datastore,Cluster,CPU,MemoryGB,CustomisationSpec,PowerOn
web01,t-ubuntu-2404,datastore1,Cluster01,2,4,Ubuntu-Spec,true
dc01,ws2025-golden,datastore1,Cluster01,4,8,Windows-Spec,true
```

Only `Name` and `Template` are mandatory — all other columns are optional.
