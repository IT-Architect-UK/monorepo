# VMware ESXi / vCenter — VM Templates & Deployment

This section covers creating golden VM templates on VMware and deploying new
virtual machines from them. Using templates is the standard approach in
enterprise environments — it ensures every server starts from a known-good,
fully-patched base, and deployment takes minutes rather than hours.

## 📋 What is VMware?

VMware is the most widely-used hypervisor platform in enterprise IT:

| Product | Purpose |
|---------|---------|
| **ESXi** | The bare-metal hypervisor — installs directly on servers and runs VMs |
| **vCenter Server** | The management layer — lets you manage multiple ESXi hosts from one UI |
| **vSphere** | The combined platform name (ESXi + vCenter) |

For home labs, you can use ESXi free (with some limitations) or the paid
vSphere Essentials licence for full vCenter features.

## 📁 Folder Structure

```
vmware/
├── templates/               # Scripts to prepare and seal "golden" templates
│   ├── prepare-windows-2025-template.ps1   # Patch, Sysprep, convert to template
│   └── prepare-ubuntu-2404-template.sh     # Patch, clean, seal for cloning
└── provisioning/            # Scripts to deploy VMs from templates
    ├── clone-from-template.ps1             # Clone a single VM
    └── deploy-vm-from-template.ps1         # Bulk deploy from a CSV file
```

## 🔄 Workflow: Template → Clone → Deploy

```
[Fresh VM]
    │
    ▼
[Install OS + configure base settings]
    │
    ▼
[Run prepare-*-template script]        ← Patches OS, installs VMware Tools,
    │                                     seals unique identifiers, shuts down
    ▼
[Convert VM to Template in vCenter]
    │
    ├─► [Clone 1] → web01
    ├─► [Clone 2] → db01
    └─► [Clone 3] → app01
```

## 🚀 Quick Start

### Step 1: Build a Golden Template

**Windows Server 2025:**
```powershell
# Run from your workstation (not the VM itself)
.\templates\prepare-windows-2025-template.ps1 `
    -vCenterServer "vcenter.lab.local" `
    -VMName "ws2025-base"
```

**Ubuntu 24.04:**
```bash
# SSH into the Ubuntu VM you want to template, then run:
sudo ./templates/prepare-ubuntu-2404-template.sh
# After shutdown, right-click the VM in vCenter → Convert to Template
```

### Step 2: Deploy VMs from the Template

**Single VM:**
```powershell
.\provisioning\clone-from-template.ps1 `
    -vCenterServer "vcenter.lab.local" `
    -TemplateName "ws2025-golden" `
    -VMName "dc01" `
    -NumCPU 4 -MemoryGB 8 `
    -PowerOn
```

**Multiple VMs from a CSV:**
```powershell
# Create vms.csv (see below), then:
.\provisioning\deploy-vm-from-template.ps1 `
    -vCenterServer "vcenter.lab.local" `
    -CsvPath ".\vms.csv"
```

Example `vms.csv`:
```csv
Name,Template,Datastore,Cluster,CPU,MemoryGB,CustomisationSpec,PowerOn
web01,t-ubuntu-2404,datastore1,Cluster01,2,4,Ubuntu-Spec,true
db01,t-ubuntu-2404,datastore1,Cluster01,4,8,Ubuntu-Spec,true
dc01,ws2025-golden,datastore1,Cluster01,4,8,Windows-Spec,true
```

## ☁️ Cloud Equivalents

| VMware Concept | AWS | Azure | GCP |
|---------------|-----|-------|-----|
| VM Template | AMI (Amazon Machine Image) | Managed Image | Machine Image |
| Sysprep / cloud-init seal | EC2 Image Builder | Azure Image Builder | Packer |
| Guest Customisation Spec | EC2 User Data | Custom Script Extension | Startup Script |
| vCenter Clone | Launch instance from AMI | VM from Managed Image | Create VM from image |
| Linked Clone | — | Shared Image Gallery | — |

## 🔧 Prerequisites

1. **PowerCLI** (for PowerShell scripts):
   ```powershell
   Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force
   ```

2. **vCenter or ESXi access** — the scripts connect via the PowerCLI API.

3. **VMware Tools** installed in the VM before templating — required for graceful
   shutdown, IP reporting, and guest script execution.

## ❓ Troubleshooting

**Sysprep fails?**
→ Ensure Windows is fully activated and that no applications block Sysprep.
→ Check `C:\Windows\System32\Sysprep\Panther\setuperr.log` for errors.

**Clone gets the same hostname?**
→ You need a vCenter Guest Customisation Spec. Create one:
  vCenter → Policies and Profiles → VM Customisation Specifications.

**PowerCLI certificate error?**
→ Add `-InvalidCertificateAction Ignore` or add your vCenter cert to trusted roots.

**Ubuntu VM not getting a new hostname after clone?**
→ Confirm cloud-init ran: `sudo cloud-init status --long`
→ Check the datasource is VMware: `sudo cloud-id`
