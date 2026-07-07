# =============================================================================
# build-ubuntu-2604-proxmox.ps1 — Ubuntu 26.04 Golden Image (Proxmox), Windows
# Standalone Packer build wrapper. The ONLY requirement on this machine is
# Packer >= 1.10 — the Ansible baseline runs inside the build VM.
#
# USAGE (from this folder in a PowerShell terminal):
#   .\build-ubuntu-2604-proxmox.ps1            # guided build
#   .\build-ubuntu-2604-proxmox.ps1 -DryRun    # init + validate only
#
# CREDENTIALS (prompted if not set):
#   $env:PKR_VAR_proxmox_password              # password auth, OR
#   $env:PKR_VAR_proxmox_username = "user@pam!tokenid"
#   $env:PKR_VAR_proxmox_token    = "<secret>" # token auth (recommended)
#
# ISO: staged automatically — the latest 26.04 live-server image is found on
# releases.ubuntu.com and downloaded BY the Proxmox host (server-side pull,
# checksum-verified) via ..\..\scripts\fetch-ubuntu-iso.ps1. To pin a specific
# pre-uploaded ISO instead:
#   $env:PKR_VAR_ubuntu_iso_file = "local:iso/ubuntu-26.04.2-live-server-amd64.iso"
#
# Site settings (proxmox_url, node, storage, VLAN) come from variables.pkr.hcl
# defaults — override any of them with $env:PKR_VAR_<name>.
# =============================================================================

param([switch]$DryRun)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$TemplateDir = $PSScriptRoot
Set-Location $TemplateDir

if (-not (Get-Command packer -ErrorAction SilentlyContinue)) {
    Write-Error "packer not found on PATH — install from https://developer.hashicorp.com/packer/downloads"
    exit 1
}

# ── Credentials: env-first, prompt-fallback ───────────────────────────────────
$hasToken    = -not [string]::IsNullOrWhiteSpace($env:PKR_VAR_proxmox_token)
$hasPassword = -not [string]::IsNullOrWhiteSpace($env:PKR_VAR_proxmox_password)
if (-not ($hasToken -or $hasPassword)) {
    Write-Host ""
    Write-Host "  No Proxmox credential in the environment (PKR_VAR_proxmox_token / PKR_VAR_proxmox_password)." -ForegroundColor Yellow
    $secure = Read-Host "  Proxmox password (input hidden; for token auth press Ctrl+C and see the script header)" -AsSecureString
    $env:PKR_VAR_proxmox_password = [System.Net.NetworkCredential]::new("", $secure).Password
}

if ([string]::IsNullOrWhiteSpace($env:PKR_VAR_ubuntu_iso_file)) {
    Write-Host ""
    Write-Host "  PKR_VAR_ubuntu_iso_file not set — staging the latest Ubuntu 26.04 ISO on Proxmox..." -ForegroundColor Yellow
    # fetch-ubuntu-iso.ps1 reuses the same PROXMOX_* env vars / prompts; the
    # ISO is downloaded BY the Proxmox host itself and checksum-verified.
    if (-not $env:PROXMOX_PASSWORD -and -not $env:PROXMOX_TOKEN_SECRET -and $env:PKR_VAR_proxmox_password) {
        $env:PROXMOX_PASSWORD = $env:PKR_VAR_proxmox_password   # reuse what the build already collected
    }
    $volid = & (Join-Path $TemplateDir "..\..\scriptsetch-ubuntu-iso.ps1") -Release "26.04" | Select-Object -Last 1
    if ([string]::IsNullOrWhiteSpace($volid)) { Write-Error "ISO staging failed — set PKR_VAR_ubuntu_iso_file manually (see header)."; exit 1 }
    $env:PKR_VAR_ubuntu_iso_file = $volid.Trim()
    Write-Host "  Using ISO: $($env:PKR_VAR_ubuntu_iso_file)" -ForegroundColor Green
}

# ── Build ─────────────────────────────────────────────────────────────────────
$LogDir = Join-Path $TemplateDir "logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$LogFile = Join-Path $LogDir "build-ubuntu-2604-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$env:PACKER_NO_COLOR = "1"

try {
    Write-Host "`n[1/3] packer init..." -ForegroundColor Cyan
    packer init . 2>&1 | Tee-Object -FilePath $LogFile -Append | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "packer init failed" }

    Write-Host "`n[2/3] packer validate..." -ForegroundColor Cyan
    packer validate . 2>&1 | Tee-Object -FilePath $LogFile -Append | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "packer validate failed" }

    if ($DryRun) {
        Write-Host "`n  DryRun complete — skipping build." -ForegroundColor Magenta
    } else {
        Write-Host "`n[3/3] packer build (15-30 min)..." -ForegroundColor Cyan
        packer build . 2>&1 | Tee-Object -FilePath $LogFile -Append | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "packer build failed" }
        Write-Host "`nDone. New template: t-ubuntu-2604-<timestamp> (VMID 9006)." -ForegroundColor Green
        Write-Host "Provision from it: Semaphore -> Task Templates -> Provision VM (Proxmox)." -ForegroundColor Green
    }
} catch {
    Write-Host "`nFAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Log: $LogFile" -ForegroundColor DarkGray
    exit 1
} finally {
    Remove-Item Env:\PACKER_NO_COLOR -ErrorAction SilentlyContinue
}
Write-Host "Log: $LogFile" -ForegroundColor DarkGray
