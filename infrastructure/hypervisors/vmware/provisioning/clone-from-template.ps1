#Requires -Version 5.1
<#
.SYNOPSIS
    Clones a VMware template to create a new virtual machine.

.DESCRIPTION
    This script connects to vCenter and clones an existing template to a new VM.
    It supports optional Guest Customisation Specifications (Customisation Spec)
    to automatically set the hostname and network configuration on first boot.

    Template cloning is the fastest way to deploy a new VM — no OS installation
    required. A clone of a 40GB template typically takes 1-5 minutes vs 30-60
    minutes for a fresh OS install.

    This is the VMware equivalent of launching an EC2 instance from an AMI or
    deploying an Azure VM from a Managed Image.

.PARAMETER vCenterServer
    Hostname or IP address of your vCenter Server.

.PARAMETER Credential
    PSCredential for vCenter. If not supplied, you will be prompted.

.PARAMETER TemplateName
    Name of the template to clone from. Run Get-Template to list available templates.

.PARAMETER VMName
    Name for the new VM.

.PARAMETER Datastore
    Target datastore for the VM files. If not specified, uses the same datastore as the template.

.PARAMETER Cluster
    Target cluster or host to place the VM on.

.PARAMETER CustomisationSpec
    Optional: Name of a vCenter Guest Customisation Spec to apply on first boot.
    The spec sets the hostname, domain, admin password, and network settings.
    Create specs in vCenter UI: Policies and Profiles → VM Customisation Specifications.

.PARAMETER PowerOn
    If specified, powers on the VM immediately after cloning.

.PARAMETER NumCPU
    Override the number of vCPUs (optional).

.PARAMETER MemoryGB
    Override the amount of RAM in GB (optional).

.EXAMPLE
    # Basic clone — same hardware as the template
    .\clone-from-template.ps1 -vCenterServer "vcenter.lab.local" -TemplateName "ws2025-golden" -VMName "dc01"

.EXAMPLE
    # Clone with customisation spec and power on
    .\clone-from-template.ps1 -vCenterServer "vcenter.lab.local" -TemplateName "ubuntu-2404-golden" -VMName "web01" -CustomisationSpec "Ubuntu-Spec" -PowerOn

.EXAMPLE
    # Clone with resource override
    .\clone-from-template.ps1 -vCenterServer "vcenter.lab.local" -TemplateName "ws2025-golden" -VMName "app01" -NumCPU 4 -MemoryGB 8 -PowerOn

.NOTES
    Prerequisites:
    - VMware.PowerCLI module: Install-Module -Name VMware.PowerCLI -Scope CurrentUser
    - vCenter (not standalone ESXi) required for Customisation Specs

    Author  : IT-Architect-UK
    Repo    : https://github.com/IT-Architect-UK/monorepo
    Version : 1.0.0
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]  [string]$vCenterServer,
    [Parameter()]           [PSCredential]$Credential,
    [Parameter(Mandatory)]  [string]$TemplateName,
    [Parameter(Mandatory)]  [string]$VMName,
    [Parameter()]           [string]$Datastore,
    [Parameter()]           [string]$Cluster,
    [Parameter()]           [string]$CustomisationSpec,
    [Parameter()]           [switch]$PowerOn,
    [Parameter()]           [int]$NumCPU,
    [Parameter()]           [int]$MemoryGB
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step   { param($m) Write-Host "[>] $m" -ForegroundColor Cyan }
function Write-OK     { param($m) Write-Host "[✔] $m" -ForegroundColor Green }
function Write-Warn   { param($m) Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-Fail   { param($m) Write-Host "[✘] $m" -ForegroundColor Red; throw $m }
function Write-Header { param($m) Write-Host "`n━━━ $m ━━━`n" -ForegroundColor Blue }

Write-Header "Clone VM from Template"

# ── Connect ────────────────────────────────────────────────────────────────
Import-Module VMware.PowerCLI -ErrorAction Stop
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null

if (-not $Credential) { $Credential = Get-Credential -Message "vCenter credentials" }
Write-Step "Connecting to $vCenterServer..."
$null = Connect-VIServer -Server $vCenterServer -Credential $Credential
Write-OK "Connected"

# ── Resolve template ────────────────────────────────────────────────────────
Write-Step "Looking up template '$TemplateName'..."
$template = Get-Template -Name $TemplateName -ErrorAction SilentlyContinue
if (-not $template) { Write-Fail "Template '$TemplateName' not found. Run: Get-Template | Select-Object Name" }
Write-OK "Template found: $($template.Name)"

# ── Resolve datastore ───────────────────────────────────────────────────────
$dsArgs = @{}
if ($Datastore) {
    Write-Step "Resolving datastore '$Datastore'..."
    $ds = Get-Datastore -Name $Datastore -ErrorAction SilentlyContinue
    if (-not $ds) { Write-Fail "Datastore '$Datastore' not found" }
    $dsArgs['Datastore'] = $ds
    Write-OK "Datastore: $($ds.Name) (Free: $([math]::Round($ds.FreeSpaceGB, 1)) GB)"
}

# ── Resolve location ────────────────────────────────────────────────────────
$locArgs = @{}
if ($Cluster) {
    Write-Step "Resolving cluster '$Cluster'..."
    $cl = Get-Cluster -Name $Cluster -ErrorAction SilentlyContinue
    if ($cl) {
        $locArgs['ResourcePool'] = ($cl | Get-ResourcePool -Name 'Resources')
        Write-OK "Cluster: $($cl.Name)"
    } else {
        # Try as individual host
        $h = Get-VMHost -Name $Cluster -ErrorAction SilentlyContinue
        if (-not $h) { Write-Fail "Cluster or host '$Cluster' not found" }
        $locArgs['VMHost'] = $h
        Write-OK "Host: $($h.Name)"
    }
}

# ── Customisation Spec ──────────────────────────────────────────────────────
$specArgs = @{}
if ($CustomisationSpec) {
    Write-Step "Looking up customisation spec '$CustomisationSpec'..."
    $spec = Get-OSCustomizationSpec -Name $CustomisationSpec -ErrorAction SilentlyContinue
    if (-not $spec) {
        Write-Warn "Customisation spec '$CustomisationSpec' not found. Cloning without customisation."
        Write-Warn "Create a spec in vCenter: Policies and Profiles → VM Customisation Specifications"
    } else {
        $specArgs['OSCustomizationSpec'] = $spec
        Write-OK "Customisation spec: $($spec.Name)"
    }
}

# ── Clone ───────────────────────────────────────────────────────────────────
Write-Header "Cloning Template → $VMName"
$stopwatch = [Diagnostics.Stopwatch]::StartNew()

Write-Step "Starting clone operation..."
$newVM = New-VM -Name $VMName -Template $template @dsArgs @locArgs @specArgs
Write-OK "Clone completed in $($stopwatch.Elapsed.ToString('mm\:ss'))"

# ── Resource overrides ──────────────────────────────────────────────────────
if ($NumCPU -or $MemoryGB) {
    Write-Step "Applying resource overrides..."
    $vmConfig = @{}
    if ($NumCPU)   { $vmConfig['NumCpu']   = $NumCPU }
    if ($MemoryGB) { $vmConfig['MemoryGB'] = $MemoryGB }
    Set-VM -VM $newVM @vmConfig -Confirm:$false | Out-Null
    Write-OK "Resources updated: vCPUs=$NumCPU, RAM=$MemoryGB GB"
}

# ── Power on ────────────────────────────────────────────────────────────────
if ($PowerOn) {
    Write-Header "Powering On"
    Write-Step "Starting VM '$VMName'..."
    Start-VM -VM $newVM | Out-Null
    Write-OK "VM powered on"

    if ($CustomisationSpec) {
        Write-Warn "Guest customisation is running. The VM may reboot once or twice."
        Write-Warn "Wait 2-5 minutes then check the VM console for the new hostname."
    }
}

# ── Summary ─────────────────────────────────────────────────────────────────
Write-Header "Deployment Summary"
$vm = Get-VM -Name $VMName
Write-OK "VM Name      : $($vm.Name)"
Write-OK "Power State  : $($vm.PowerState)"
Write-OK "vCPUs        : $($vm.NumCpu)"
Write-OK "Memory       : $($vm.MemoryGB) GB"
Write-OK "Guest OS     : $($vm.Guest.OSFullName)"

if ($vm.PowerState -eq 'PoweredOn' -and $vm.Guest.IPAddress) {
    Write-OK "IP Address   : $($vm.Guest.IPAddress[0])"
}

Write-Host ""
Write-Host "The VM is ready. Next steps:" -ForegroundColor Cyan
if ($vm.PowerState -ne 'PoweredOn') {
    Write-Host "  1. Power on the VM: Start-VM -VM '$VMName'"
} else {
    Write-Host "  1. VM is already running — check the console or SSH in"
}
Write-Host "  2. Complete any post-deployment tasks (join domain, configure app)"
Write-Host ""

Disconnect-VIServer -Server $vCenterServer -Confirm:$false
