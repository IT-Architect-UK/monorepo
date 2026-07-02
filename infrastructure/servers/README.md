# Servers

Day-1 configuration scripts for Linux and Windows servers.

## Linux (Ubuntu) — `linux/configuration/`

`server-baseline.sh` orchestrates the standard set below against a fresh server — run that for a full baseline, or any script standalone. Usage in each header.

| Script | Purpose |
|--------|---------|
| `server-baseline.sh` | **Start here** — runs the standard baseline sequence |
| `apt-get-upgrade.sh` | Full non-interactive system upgrade + cleanup |
| `apply-branding.sh` | Login banner, MOTD, and prompt branding |
| `create-user.sh` | Create a user with optional sudo + SSH key (idempotent) |
| `disable-cloud-init.sh` | Stop cloud-init running on future boots (post-provisioning) |
| `disable-ipv6.sh` | Persistently disable IPv6 via sysctl |
| `install-tls-certificate.sh` | Certbot (snap) + Let's Encrypt cert for Apache/Nginx |
| `sync-monorepo.sh` | Clone/pull this repo to `/git/monorepo` (installed to `/usr/local/bin` on toolbox builds) |

## Windows — `windows/`

Elevated PowerShell; all have comment-based help (`Get-Help .\<script>.ps1 -Full`).

| Script | Purpose |
|--------|---------|
| `os/create-local-admin.ps1` | Create a local administrator account |
| `os/rename-computer.ps1` | Rename the computer (optional restart) |
| `os/run-windows-update.ps1` | Install all pending Windows updates |
| `os/setup-hdds.ps1` | Initialise, partition, and format new disks |
| `os/reset-local-policies.ps1` | Reset local security policies to defaults |
| `os/Sync-Monorepo.ps1` | Clone/pull this repo locally |
| `packages/install-chocolatey-packages.ps1` | Install Chocolatey + a standard package set |
