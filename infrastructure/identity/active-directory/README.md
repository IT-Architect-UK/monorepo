# Active Directory

PowerShell automation for standing up and baselining an AD DS environment on Windows Server. Run in an elevated PowerShell session; each script has a full comment-based help block (`Get-Help .\<script>.ps1 -Full`).

| Script | Purpose | Run on |
|--------|---------|--------|
| `install-adds-new-forest.ps1` | Install the AD DS role and promote to the first DC of a **new forest** (reboots when done) | The server becoming DC |
| `install-adds-rsat.ps1` | Install RSAT AD management tools | Any management server |
| `add-adds-baseline-objects.ps1` | One-pass baseline for a new forest: enables the AD Recycle Bin, renames `Default-First-Site-Name` (`-NewSiteName`, default `ADDS-Site-1`) and creates a replication subnet from the server's own IPv4 address, creates the standard OU tree (blocking GPO inheritance on `Block All GPOs`, redirecting new computers to `Staging`), creates the `SVR-*` / `RBAG-*` security groups and adds `-AdminUser` (default `Administrator`) to `RBAG-SVR-Admin` | A DC / RSAT host |
| `ou/add-baseline-ou-objects.ps1` | Create the baseline OU structure only (domain-member and Domain Admin checks first) | A DC / RSAT host |
| `groups/create-ad-server-admins-group.ps1` | Create the Server Admins security group | A DC / RSAT host |

**Known issue:** the comment-based help in `ou/add-baseline-ou-objects.ps1` is
a copy of the full baseline script's and describes site, Recycle Bin and group
work the OU script does not do. Trust the table above for that one.

## Typical order

```powershell
.\install-adds-new-forest.ps1      # new environment — reboots
.\add-adds-baseline-objects.ps1    # after DC promotion
```
