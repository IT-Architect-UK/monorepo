#Requires -Version 5.1
<#
.SYNOPSIS
    Deploys multiple VMs from a VMware template in a single operation.

.DESCRIPTION
    This script reads a CSV file defining one or more VMs to deploy, then clones
    the specified template for each VM in parallel. Use this when you need to
    spin up several servers at once — for example, building a new lab environment
    or deploying a multi-tier application stack.

    CSV format example (save as vms.csv):
        Name,Template,Datastore,Cluster,CPU,MemoryGB,CustomisationSpec,PowerOn
        web01,ubuntu-2404-golden,datastore1,Cluster01,2,4,Ubuntu-Spec,true
        db01,ubuntu-2404-golden,datastore1,Cluster01,4,8,Ubuntu-Spec,true
        dc01,ws2025-golden,datastore1,Cluster01,4,8,Windows-Spec,true

.PARAMETER vCenterServer
    Hostname or IP address of vCenter.

.PARAMETER Credential
    PSCredential for vCenter. If omitted, you will be prompted.

.PARAMETER CsvPath
    Path to the CSV file defining the VMs to deploy. See description for format.

.PARAMETER WaitForCompletion
    If specified, wait for all clones to complete before returning.

.EXAMPLE
    .\deploy-vm-from-template.ps1 -vCenterServer "vcenter.lab.local" -CsvPath ".\vms.csv"

.EXAMPLE
    .\deploy-vm-from-template.ps1 -vCenterServer "vcenter.lab.local" -CsvPath ".\vms.csv" -WaitForCompletion

.NOTES
    Author  : IT-Architect-UK
    Repo    : https://github.com/IT-Architect-UK/monorepo
    Version : 1.0.0
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string]$vCenterServer,
    [Parameter()]          [PSCredential]$Credential,
    [Parameter(Mandatory)] [string]$CsvPath,
    [Parameter()]          [switch]$WaitForCompletion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step   { param($m) Write-Host "[>] $m" -ForegroundColor Cyan }
function Write-OK     { param($m) Write-Host "[✔] $m" -ForegroundColor Green }
function Write-Warn   { param($m) Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-Fail   { param($m) Write-Host "[✘] $m" -ForegroundColor Red; throw $m }
function Write-Header { param($m) Write-Host "`n━━━ $m ━━━`n" -ForegroundColor Blue }

Write-Header "Bulk VM Deployment from Templates"

# ── Validate CSV ───────────────────────────────────────────────────────────
if (-not (Test-Path $CsvPath)) { Write-Fail "CSV file not found: $CsvPath" }
$vmList = Import-Csv -Path $CsvPath
Write-OK "Loaded $($vmList.Count) VM definition(s) from $CsvPath"

# ── Required CSV columns ────────────────────────────────────────────────────
$required = @('Name','Template')
foreach ($col in $required) {
    if ($col -notin $vmList[0].PSObject.Properties.Name) {
        Write-Fail "CSV is missing required column: '$col'"
    }
}

# ── Connect ────────────────────────────────────────────────────────────────
Import-Module VMware.PowerCLI -ErrorAction Stop
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null
if (-not $Credential) { $Credential = Get-Credential -Message "vCenter credentials" }
$null = Connect-VIServer -Server $vCenterServer -Credential $Credential
Write-OK "Connected to $vCenterServer"

# ── Pre-flight checks ───────────────────────────────────────────────────────
Write-Header "Pre-flight Checks"
foreach ($row in $vmList) {
    $tmpl = Get-Template -Name $row.Template -ErrorAction SilentlyContinue
    if (-not $tmpl) { Write-Fail "Template '$($row.Template)' not found (required for VM '$($row.Name)')" }
    Write-OK "Template OK: $($row.Template)"

    $existing = Get-VM -Name $row.Name -ErrorAction SilentlyContinue
    if ($existing) { Write-Warn "VM '$($row.Name)' already exists — will skip" }
}

# ── Deploy ─────────────────────────────────────────────────────────────────
Write-Header "Deploying VMs"
$cloneScript = "$PSScriptRoot\clone-from-template.ps1"

foreach ($row in $vmList) {
    $existing = Get-VM -Name $row.Name -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Warn "Skipping '$($row.Name)' — already exists"
        continue
    }

    Write-Step "Deploying $($row.Name) from $($row.Template)..."

    $cloneArgs = @{
        vCenterServer  = $vCenterServer
        Credential     = $Credential
        TemplateName   = $row.Template
        VMName         = $row.Name
    }
    if ($row.Datastore)          { $cloneArgs['Datastore']          = $row.Datastore }
    if ($row.Cluster)            { $cloneArgs['Cluster']            = $row.Cluster }
    if ($row.CPU -and $row.CPU -ne '') { $cloneArgs['NumCPU']      = [int]$row.CPU }
    if ($row.MemoryGB -and $row.MemoryGB -ne '') { $cloneArgs['MemoryGB'] = [int]$row.MemoryGB }
    if ($row.CustomisationSpec -and $row.CustomisationSpec -ne '') {
        $cloneArgs['CustomisationSpec'] = $row.CustomisationSpec
    }
    if ($row.PowerOn -eq 'true') { $cloneArgs['PowerOn'] = $true }

    & $cloneScript @cloneArgs
    Write-OK "Deployed: $($row.Name)"
}

Write-Header "All Deployments Complete"
Write-OK "$($vmList.Count) VM(s) processed"

Disconnect-VIServer -Server $vCenterServer -Confirm:$false
