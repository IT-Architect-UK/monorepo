# =============================================================================
# cleanup-automation-toolbox-proxmox.ps1
# Deletes the automation-toolbox Packer template and/or cloned test server
# from Proxmox, so a fresh build/test cycle can start clean.
#
# LOCATION: automation/packer/builds/ubuntu-2404-automation-toolbox/
#
# What it does:
#   1. Connects to the Proxmox API (same host/credentials as the build)
#   2. Finds the template (default VM ID 9002) and any VM whose name you give
#   3. Shows exactly what it found and asks for confirmation
#   4. Stops the clone if it is running, then deletes clone and template
#
# USAGE (from this folder in a PowerShell terminal):
#   .\cleanup-automation-toolbox-proxmox.ps1                      # template 9002 + clones named POSLXPDEPLOY01
#   .\cleanup-automation-toolbox-proxmox.ps1 -CloneName MYTEST01  # different clone name
#   .\cleanup-automation-toolbox-proxmox.ps1 -TemplateOnly        # leave the clone alone
#   .\cleanup-automation-toolbox-proxmox.ps1 -CloneOnly           # leave the template alone
#   .\cleanup-automation-toolbox-proxmox.ps1 -Force               # skip the confirmation prompt
#
# CREDENTIALS: uses the same env var as the build script
# (PKR_VAR_proxmox_password) and prompts if it isn't set. Nothing is
# written to disk.
# =============================================================================

param(
    [int]    $TemplateId   = 9002,
    [string] $CloneName    = "POSLXPDEPLOY01",
    [string] $ProxmoxUrl   = "https://192.168.4.150:8006",
    [string] $ProxmoxUser  = "root@pam",
    [string] $Node         = "POSVMPWS01",
    [switch] $TemplateOnly,
    [switch] $CloneOnly,
    [switch] $Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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
    if ($IsPS7) { $req.SkipCertificateCheck = $true }
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

if (-not $CloneOnly) {
    $tpl = $vms | Where-Object { $_.vmid -eq $TemplateId }
    if ($tpl) {
        if ((Get-Prop $tpl 'template') -ne 1) {
            Write-Warning "VM $TemplateId ('$($tpl.name)') is NOT a template — skipping it. Use -CloneName to delete regular VMs."
        } else {
            $targets += $tpl
        }
    } else {
        Write-Host "No template with VM ID $TemplateId found — nothing to do there." -ForegroundColor DarkGray
    }
}

if (-not $TemplateOnly) {
    $clones = $vms | Where-Object { $_.name -eq $CloneName -and $_.vmid -ne $TemplateId -and (Get-Prop $_ 'template') -ne 1 }
    if ($clones) { $targets += $clones }
    else { Write-Host "No VM named '$CloneName' found — nothing to do there." -ForegroundColor DarkGray }
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

Write-Host "`nCleanup complete — ready for a fresh build." -ForegroundColor Green
