# =============================================================================
# cleanup-automation-toolbox-proxmox.ps1
# Deletes the automation-toolbox Packer template and/or cloned test server
# from Proxmox, so a fresh build/test cycle can start clean.
#
# LOCATION: automation/packer/builds/ubuntu-2404-automation-toolbox/
#
# What it does:
#   1. Connects to the Proxmox API (same host/credentials as the build)
#   2. Finds the toolbox template (VM ID 9002), the cloned toolbox VM (by name),
#      and the golden image templates (VM IDs 9003/9004/9006 by default)
#   3. Shows exactly what it found and asks for confirmation
#   4. Stops any running VM, then deletes every confirmed target
#   5. Purges local build artefacts (manifest, packer_cache/, .tmp/, logs/)
#      so the next build starts clean
#
# SCOPE / SAFETY: only the specific VM IDs above and the named clone are ever
# touched. Your other VMs and templates are never selected. A golden ID is only
# deleted if the VM at that ID is actually a template. Nothing runs without you
# typing 'yes' at the confirmation (unless -Force).
#
# USAGE (from this folder in a PowerShell terminal):
#   .\cleanup-automation-toolbox-proxmox.ps1                      # toolbox template + clone + goldens (all)
#   .\cleanup-automation-toolbox-proxmox.ps1 -KeepGolden          # toolbox template + clone, keep goldens
#   .\cleanup-automation-toolbox-proxmox.ps1 -GoldenOnly          # only the golden templates
#   .\cleanup-automation-toolbox-proxmox.ps1 -TemplateOnly        # only the toolbox template (9002)
#   .\cleanup-automation-toolbox-proxmox.ps1 -CloneOnly           # only the cloned toolbox VM
#   .\cleanup-automation-toolbox-proxmox.ps1 -CloneName MYTEST01  # different clone name
#   .\cleanup-automation-toolbox-proxmox.ps1 -GoldenIds 9003,9004 # override golden VM IDs
#   .\cleanup-automation-toolbox-proxmox.ps1 -Force               # skip the confirmation prompt
#
# CREDENTIALS: uses the same env var as the build script
# (PKR_VAR_proxmox_password) and prompts if it isn't set. Nothing is
# written to disk.
# =============================================================================

param(
    [int]    $TemplateId   = 9002,
    [string] $CloneName    = "POSLXPDEPLOY01",
    [int[]]  $GoldenIds    = @(9003, 9004, 9006),
    [string] $ProxmoxUrl   = "",
    [string] $ProxmoxUser  = "root@pam",
    [string] $Node         = "",
    [switch] $TemplateOnly,
    [switch] $CloneOnly,
    [switch] $GoldenOnly,
    [switch] $KeepGolden,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Site defaults from the repo's single site file (environments/homelab.pkrvars.hcl)
$siteFile = Join-Path $PSScriptRoot "..\..\environments\homelab.pkrvars.hcl"
if (Test-Path $siteFile) {
    if (-not $ProxmoxUrl) {
        $m = Select-String -Path $siteFile -Pattern '^\s*proxmox_url\s*=\s*"(https?://[^:/"]+)' | Select-Object -First 1
        if ($m) { $ProxmoxUrl = $m.Matches[0].Groups[1].Value + ":8006" }
    }
    if (-not $Node) {
        $m = Select-String -Path $siteFile -Pattern '^\s*proxmox_node\s*=\s*"([^"]+)"' | Select-Object -First 1
        if ($m) { $Node = $m.Matches[0].Groups[1].Value }
    }
}
if (-not $ProxmoxUrl) { $ProxmoxUrl = "https://" + (Read-Host "Proxmox API host") + ":8006" }
if (-not $Node)       { $Node = Read-Host "Proxmox node name" }

# ── TLS: Proxmox uses a self-signed certificate ──────────────────────────────
# PowerShell 7 has -SkipCertificateCheck; Windows PowerShell 5.1 needs the
# ServicePointManager escape hatch.
$IsPS7 = $PSVersionTable.PSVersion.Major -ge 6
if (-not $IsPS7) {
    Add-Type -TypeDefinition @"
using System.Net; using System.Security.Cryptography.X509Certificates;
public class TrustAll : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint sp, X509Certificate c, WebRequest r, int p) { return true; }
}
"@
    [System.Net.ServicePointManager]::CertificatePolicy = [TrustAll]::new()
    [System.Net.ServicePointManager]::SecurityProtocol  = [System.Net.SecurityProtocolType]::Tls12
}

function Get-Prop {
    # StrictMode-safe property read — cluster/resources omits some fields
    # (e.g. 'template') on objects where they don't apply.
    param($Object, [string]$Name)
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { $p.Value } else { $null }
}

function Invoke-Pve {
    param([string]$Method, [string]$Path, [hashtable]$Body = $null)
    $req = @{
        Method  = $Method
        Uri     = "$ProxmoxUrl/api2/json$Path"
        Headers = $script:PveHeaders
    }
    if ($Body)  { $req.Body = $Body }
    if ($IsPS7) { $req.SkipCertificateCheck = $true; $req.SkipHeaderValidation = $true }
    (Invoke-RestMethod @req).data
}

# ── Authenticate ─────────────────────────────────────────────────────────────
$password = $env:PKR_VAR_proxmox_password
if (-not $password) {
    $secure   = Read-Host "Proxmox password for $ProxmoxUser" -AsSecureString
    $password = [System.Net.NetworkCredential]::new("", $secure).Password
}

Write-Host "Authenticating to $ProxmoxUrl as $ProxmoxUser..." -ForegroundColor Cyan
$script:PveHeaders = @{}
$ticket = Invoke-Pve POST "/access/ticket" @{ username = $ProxmoxUser; password = $password }
$script:PveHeaders = @{
    Cookie              = "PVEAuthCookie=$($ticket.ticket)"
    CSRFPreventionToken = $ticket.CSRFPreventionToken
}

# ── Discover targets ─────────────────────────────────────────────────────────
$vms = Invoke-Pve GET "/cluster/resources?type=vm"
$targets = @()

# Which groups to act on. Default (no switches) = all three.
$doTemplate = -not ($CloneOnly -or $GoldenOnly)
$doClone    = -not ($TemplateOnly -or $GoldenOnly)
$doGolden   = -not ($TemplateOnly -or $CloneOnly -or $KeepGolden)

if ($doTemplate) {
    $tpl = $vms | Where-Object { $_.vmid -eq $TemplateId }
    if ($tpl) {
        if ((Get-Prop $tpl 'template') -ne 1) {
            Write-Warning "VM $TemplateId ('$($tpl.name)') is NOT a template — skipping it (safety)."
        } else {
            $targets += $tpl
        }
    } else {
        Write-Host "No toolbox template with VM ID $TemplateId found — skipping." -ForegroundColor DarkGray
    }
}

if ($doClone) {
    $clones = $vms | Where-Object { $_.name -eq $CloneName -and $_.vmid -ne $TemplateId -and (Get-Prop $_ 'template') -ne 1 }
    if ($clones) { $targets += $clones }
    else { Write-Host "No VM named '$CloneName' found — skipping." -ForegroundColor DarkGray }
}

if ($doGolden) {
    foreach ($gid in $GoldenIds) {
        $g = $vms | Where-Object { $_.vmid -eq $gid }
        if ($g) {
            if ((Get-Prop $g 'template') -ne 1) {
                Write-Warning "VM $gid ('$($g.name)') is NOT a template — skipping it (safety)."
            } else {
                $targets += $g
            }
        } else {
            Write-Host "No golden template with VM ID $gid found — skipping." -ForegroundColor DarkGray
        }
    }
}

if (-not $targets) { Write-Host "Nothing to delete. Done." -ForegroundColor Green; exit 0 }

# ── Confirm ──────────────────────────────────────────────────────────────────
Write-Host "`nAbout to DELETE from node ${Node}:" -ForegroundColor Yellow
$targets | ForEach-Object {
    $kind = if ((Get-Prop $_ 'template') -eq 1) { "template" } else { "VM ($($_.status))" }
    Write-Host ("  {0,-6} {1,-20} {2}" -f $_.vmid, $_.name, $kind) -ForegroundColor Yellow
}
if (-not $Force) {
    $answer = Read-Host "`nType 'yes' to confirm"
    if ($answer -ne "yes") { Write-Host "Aborted — nothing deleted." -ForegroundColor Red; exit 1 }
}

# ── Delete ───────────────────────────────────────────────────────────────────
function Wait-PveTask {
    param([string]$Upid)
    while ($true) {
        $t = Invoke-Pve GET "/nodes/$Node/tasks/$([uri]::EscapeDataString($Upid))/status"
        if ($t.status -eq "stopped") {
            if ($t.exitstatus -ne "OK") { throw "Proxmox task failed: $($t.exitstatus)" }
            return
        }
        Start-Sleep -Seconds 2
    }
}

foreach ($vm in $targets) {
    if ((Get-Prop $vm 'template') -ne 1 -and $vm.status -eq "running") {
        Write-Host "Stopping VM $($vm.vmid) ('$($vm.name)')..." -ForegroundColor Cyan
        $upid = Invoke-Pve POST "/nodes/$Node/qemu/$($vm.vmid)/status/stop" @{}
        Wait-PveTask $upid
    }
    Write-Host "Deleting $($vm.vmid) ('$($vm.name)')..." -ForegroundColor Cyan
    $upid = Invoke-Pve DELETE "/nodes/$Node/qemu/$($vm.vmid)?purge=1&destroy-unreferenced-disks=1"
    Wait-PveTask $upid
    Write-Host "  Deleted." -ForegroundColor Green
}

# ── Purge local build artefacts (manifest, cache, temp, logs) ────────────────
# Logs are reviewed before cleanup, so a fresh build starts with fresh logs.
Write-Host "`nPurging local build artefacts..." -ForegroundColor Cyan
$artefacts = @(
    "packer-manifest-automation-toolbox.json",
    "packer-manifest-automation-toolbox.json.lock",
    "packer_cache",
    ".tmp",
    "logs"
) | ForEach-Object { Join-Path $PSScriptRoot $_ }
$purged = 0
foreach ($a in $artefacts) {
    if (Test-Path $a) {
        try { Remove-Item $a -Recurse -Force -ErrorAction Stop
              Write-Host "  Removed $a" -ForegroundColor DarkGray; $purged++ }
        catch { Write-Host "  Could not remove $a : $($_.Exception.Message)" -ForegroundColor Yellow }
    }
}
Write-Host "  $purged artefact(s) purged." -ForegroundColor DarkGray

Write-Host "`nCleanup complete — ready for a fresh build." -ForegroundColor Green
