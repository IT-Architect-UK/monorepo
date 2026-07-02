# Active Directory

PowerShell automation for standing up and baselining an AD DS environment on Windows Server. Run in an elevated PowerShell session; each script has a full comment-based help block (`Get-Help .\<script>.ps1 -Full`).

| Script | Purpose | Run on |
|--------|---------|--------|
| `install-adds-new-forest.ps1` | Install the AD DS role and promote to the first DC of a **new forest** (reboots when done) | The server becoming DC |
| `install-adds-rsat.ps1` | Install RSAT AD management tools | Any management server |
| `add-adds-baseline-objects.ps1` | Create the standard baseline of OUs and groups in one pass | A DC / RSAT host |
| `ou/add-baseline-ou-objects.ps1` | Create the baseline OU structure only | A DC / RSAT host |
| `groups/create-ad-server-admins-group.ps1` | Create the Server Admins security group | A DC / RSAT host |

## Typical order

```powershell
.\install-adds-new-forest.ps1      # new environment — reboots
.\add-adds-baseline-objects.ps1    # after DC promotion
```
