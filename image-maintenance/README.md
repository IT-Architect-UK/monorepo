# Image Maintenance — Keeping Templates Fresh

VM templates and cloud machine images should be updated regularly — typically monthly. Stale images mean every new server starts behind on patches, increasing your attack surface from day one.

## 📁 Folder Structure

```
image-maintenance/
├── linux/
│   └── update-proxmox-template.sh      # Update Proxmox cloud-init template
├── windows/
│   └── sysprep-and-seal.ps1            # Sysprep Windows VM for templating
└── cloud/
    ├── aws/
    │   └── build-golden-ami.sh         # Build and update AWS AMI
    ├── azure/
    │   └── update-managed-image.sh     # Update Azure Managed Image
    └── gcp/
        └── update-machine-image.sh     # Update GCP Machine Image
```

## 🔄 Recommended Maintenance Schedule

| Task | Frequency | Script |
|------|-----------|--------|
| Update Proxmox Linux template | Monthly | `linux/update-proxmox-template.sh` |
| Rebuild Windows template | Monthly | `windows/sysprep-and-seal.ps1` |
| Rebuild AWS golden AMI | Monthly | `cloud/aws/build-golden-ami.sh` |
| Update Azure Managed Image | Monthly | `cloud/azure/update-managed-image.sh` |
| Update GCP Machine Image | Monthly | `cloud/gcp/update-machine-image.sh` |

## 🚀 Quick Reference

### Proxmox — Update Linux Template
```bash
# Run on Proxmox host as root
sudo ./linux/update-proxmox-template.sh \
    --template-id 9000 \
    --ssh-key ~/.ssh/id_rsa
```

### Windows — Sysprep and Seal (run inside the Windows VM)
```powershell
# Run as Administrator on the Windows VM
.\windows\sysprep-and-seal.ps1
# VM shuts down → then convert to template in vCenter/Proxmox
```

### AWS — Build Golden AMI
```bash
./cloud/aws/build-golden-ami.sh --region eu-west-2 --name "t-ubuntu-2404"
```

### Azure — Update Managed Image
```bash
./cloud/azure/update-managed-image.sh \
    --resource-group myRG \
    --image-name t-ubuntu-2404
```

### GCP — Update Machine Image
```bash
./cloud/gcp/update-machine-image.sh \
    --instance template-vm \
    --project my-project
```

## ☁️ Cloud Equivalents

| On-Premises | AWS | Azure | GCP |
|------------|-----|-------|-----|
| Proxmox template | AMI | Managed Image | Machine Image |
| Sysprep / cloud-init clean | EC2 Image Builder | Azure Image Builder | Custom Image |
| qm template 9000 | Create AMI | Generalise + Capture | Machine Image create |

## 💡 Best Practices

1. **Label every image with a build date** — you need to know which image is newest
2. **Test before retiring** — launch a VM from the new image before deleting the old one
3. **Keep 2-3 generations** — if the new image has a problem, fall back to the previous one
4. **Automate the build** — use a CI pipeline or cron job to build images monthly
5. **Scan for vulnerabilities** — AWS Inspector, Azure Defender, or Trivy can scan images
