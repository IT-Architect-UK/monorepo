# =============================================================================
# build-win2025-proxmox.ps1 — Windows Server 2025 Golden Image (Proxmox)
# Standalone Packer build wrapper for Windows. Only requirement on this
# machine is Packer >= 1.10 — provisioning runs in-guest via WinRM.
#
# USAGE (from this folder in a PowerShell terminal):
#   .\build-win2025-proxmox.ps1            # guided build
#   .\build-win2025-proxmox.ps1 -DryRun    # init + validate only
#
# CREDENTIALS (prompted if not set):
#   $env:PKR_VAR_proxmox_password             # password auth, OR
#   $env:PKR_VAR_proxmox_username = "user@pam!tokenid"
#   $env:PKR_VAR_proxmox_token    = "<secret>"
#   $env:PKR_VAR_winrm_password               # injected into the unattended install
#
# ISOs:
#   $env:PKR_VAR_win_iso_file    — Windows Server 2025 ISO volid; MANUAL
#     upload required (Microsoft licensing — eval ISO from the Microsoft
#     Evaluation Center), e.g. local:iso/windows-server-2025.iso
#   $env:PKR_VAR_virtio_iso_file — staged AUTOMATICALLY from the stable
#     upstream URL when unset (..\..\scripts\fetch-ubuntu-iso.ps1 URL mode
#     is not needed: the .sh handles Semaphore; here we prompt or default)
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
    $secure = Read-Host "Proxmox password (input hidden; for token auth see the script header)" -AsSecureString
    $env:PKR_VAR_proxmox_password = [System.Net.NetworkCredential]::new("", $secure).Password
}

if ([string]::IsNullOrWhiteSpace($env:PKR_VAR_winrm_password)) {
    $secure = Read-Host "WinRM build-account password — injected into the unattended install [PackerBuild2025!] (input hidden)" -AsSecureString
    $wp = [System.Net.NetworkCredential]::new("", $secure).Password
    if ([string]::IsNullOrWhiteSpace($wp)) { $wp = "PackerBuild2025!" }
    $env:PKR_VAR_winrm_password = $wp
}

if ([string]::IsNullOrWhiteSpace($env:PKR_VAR_win_iso_file)) {
    Write-Host "Choose the Windows Server 2025 ISO — pick one already on Proxmox storage, or upload from a local folder." -ForegroundColor Yellow
    if (-not $env:PROXMOX_PASSWORD -and -not $env:PROXMOX_TOKEN_SECRET -and $env:PKR_VAR_proxmox_password) {
        $env:PROXMOX_PASSWORD = $env:PKR_VAR_proxmox_password
    }
    $volid = & (Join-Path $TemplateDir "..\..\scripts\select-or-upload-iso.ps1") | Select-Object -Last 1
    if ([string]::IsNullOrWhiteSpace($volid)) { Write-Error "ISO selection failed — set PKR_VAR_win_iso_file manually."; exit 1 }
    $env:PKR_VAR_win_iso_file = $volid.Trim()
    Write-Host "Using Windows ISO: $($env:PKR_VAR_win_iso_file)" -ForegroundColor Green
}

if ([string]::IsNullOrWhiteSpace($env:PKR_VAR_virtio_iso_file)) {
    Write-Host "PKR_VAR_virtio_iso_file not set — staging virtio-win.iso on Proxmox..." -ForegroundColor Yellow
    if (-not $env:PROXMOX_PASSWORD -and -not $env:PROXMOX_TOKEN_SECRET -and $env:PKR_VAR_proxmox_password) {
        $env:PROXMOX_PASSWORD = $env:PKR_VAR_proxmox_password
    }
    $volid = & (Join-Path $TemplateDir "..\..\scripts\fetch-ubuntu-iso.ps1") `
        -Release "url" -DirectUrl "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso" |
        Select-Object -Last 1
    if ([string]::IsNullOrWhiteSpace($volid)) { Write-Error "virtio ISO staging failed — set PKR_VAR_virtio_iso_file manually."; exit 1 }
    $env:PKR_VAR_virtio_iso_file = $volid.Trim()
    Write-Host "Using virtio ISO: $($env:PKR_VAR_virtio_iso_file)" -ForegroundColor Green
}

# ── Build ─────────────────────────────────────────────────────────────────────
$LogDir = Join-Path $TemplateDir "logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$LogFile = Join-Path $LogDir "build-win2025-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
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
        Write-Host "`n[3/3] packer build (30-60 min — Windows installs are slow)..." -ForegroundColor Cyan
        packer build . 2>&1 | Tee-Object -FilePath $LogFile -Append | ForEach-Object { Write-Host $_ }
        if ($LASTEXITCODE -ne 0) { throw "packer build failed" }
        Write-Host "`nDone. New template: win2025-golden-<timestamp>." -ForegroundColor Green
    }
} catch {
    Write-Host "`nFAILED: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Log: $LogFile" -ForegroundColor DarkGray
    exit 1
} finally {
    Remove-Item Env:\PACKER_NO_COLOR -ErrorAction SilentlyContinue
}
Write-Host "Log: $LogFile" -ForegroundColor DarkGray
