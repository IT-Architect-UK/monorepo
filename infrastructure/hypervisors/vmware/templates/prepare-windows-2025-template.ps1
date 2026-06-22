#Requires -Version 5.1
<#
.SYNOPSIS
    Prepares a Windows Server 2025 VM as a reusable VMware template.

.DESCRIPTION
    This script connects to a vCenter Server or standalone ESXi host, installs
    the latest Windows updates, installs VMware Tools, runs Sysprep to generalise
    the OS, then converts the VM to a template.

    What is a VMware template?
    --------------------------
    A template is a "master copy" of a VM that is locked and cannot be powered on.
    You clone the template to create new VMs instantly — no OS installation needed.
    This is the VMware equivalent of an AWS AMI or Azure Managed Image.

    Why Sysprep?
    ------------
    When you clone a Windows VM, the clone has the same SID (Security Identifier)
    and hostname as the original. This causes Active Directory and licensing issues.
    Sysprep "generalises" the OS — removing the unique identifiers so each clone
    gets fresh ones on first boot. Think of it as resetting the OS back to a
    "factory state" that is safe to clone.

.PARAMETER vCenterServer
    Hostname or IP address of your vCenter Server or ESXi host.

.PARAMETER Credential
    PSCredential object for vCenter/ESXi login. If not supplied, you will be prompted.

.PARAMETER VMName
    Name of the existing VM to prepare as a template. The VM must be powered on
    and have a working network connection.

.PARAMETER TemplateName
    Name for the resulting template. Defaults to "<VMName>-template".

.PARAMETER SkipWindowsUpdate
    Skip the Windows Update step (use if updates were already applied).

.PARAMETER SkipVMwareTools
    Skip VMware Tools installation (use if already installed and up to date).

.EXAMPLE
    .\prepare-windows-2025-template.ps1 -vCenterServer "vcenter.lab.local" -VMName "ws2025-base"

.EXAMPLE
    $cred = Get-Credential
    .\prepare-windows-2025-template.ps1 -vCenterServer "192.168.1.10" -VMName "ws2025-base" -TemplateName "ws2025-golden" -Credential $cred

.NOTES
    Prerequisites:
    - PowerCLI module: Install-Module -Name VMware.PowerCLI -Scope CurrentUser
    - The VM must be powered on and reachable via VMware Tools
    - You need Administrator credentials for the VM's guest OS
    - vCenter/ESXi admin credentials

    Author  : IT-Architect-UK
    Repo    : https://github.com/IT-Architect-UK/monorepo
    Version : 1.0.0
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$vCenterServer,

    [Parameter()]
    [PSCredential]$Credential,

    [Parameter(Mandatory)]
    [string]$VMName,

    [Parameter()]
    [string]$TemplateName,

    [Parameter()]
    [switch]$SkipWindowsUpdate,

    [Parameter()]
    [switch]$SkipVMwareTools
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region ── Colour helpers ─────────────────────────────────────────────────────
function Write-Step   { param($m) Write-Host "[>] $m" -ForegroundColor Cyan }
function Write-OK     { param($m) Write-Host "[✔] $m" -ForegroundColor Green }
function Write-Warn   { param($m) Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-Fail   { param($m) Write-Host "[✘] $m" -ForegroundColor Red; throw $m }
function Write-Header { param($m) Write-Host "`n━━━ $m ━━━`n" -ForegroundColor Blue }
#endregion

Write-Header "Windows Server 2025 — Golden Template Builder"

#region ── 1. Check PowerCLI ────────────────────────────────────────────────
Write-Step "Checking VMware PowerCLI..."
if (-not (Get-Module -ListAvailable -Name VMware.PowerCLI)) {
    Write-Warn "VMware.PowerCLI not found. Installing from PSGallery..."
    Install-Module -Name VMware.PowerCLI -Scope CurrentUser -Force -AllowClobber
}
Import-Module VMware.PowerCLI -ErrorAction Stop
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null
Write-OK "PowerCLI ready"
#endregion

#region ── 2. Connect to vCenter ────────────────────────────────────────────
Write-Header "Connecting to vCenter/ESXi"
if (-not $Credential) {
    $Credential = Get-Credential -Message "Enter vCenter/ESXi credentials"
}

Write-Step "Connecting to $vCenterServer..."
$null = Connect-VIServer -Server $vCenterServer -Credential $Credential
Write-OK "Connected to $vCenterServer"
#endregion

#region ── 3. Locate the VM ─────────────────────────────────────────────────
Write-Header "Locating VM: $VMName"
$vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if (-not $vm) { Write-Fail "VM '$VMName' not found on $vCenterServer" }
if ($vm.PowerState -ne 'PoweredOn') { Write-Fail "VM '$VMName' must be powered on to prepare the template" }
Write-OK "Found VM: $($vm.Name) | State: $($vm.PowerState)"
#endregion

#region ── 4. Get guest credentials ─────────────────────────────────────────
Write-Header "Guest OS Access"
Write-Warn "We need Administrator credentials for the Windows guest OS."
Write-Warn "These are used to run Windows Update and Sysprep inside the VM."
$guestCred = Get-Credential -Message "Enter local Administrator credentials for $VMName guest OS"
#endregion

#region ── 5. Install / update VMware Tools ─────────────────────────────────
if (-not $SkipVMwareTools) {
    Write-Header "VMware Tools — Install / Update"
    Write-Step "Checking VMware Tools status..."
    $toolsStatus = $vm.ExtensionData.Guest.ToolsStatus
    Write-Step "Current Tools status: $toolsStatus"

    if ($toolsStatus -in @('toolsNotInstalled', 'toolsOld')) {
        Write-Step "Initiating VMware Tools update..."
        Update-Tools -VM $vm -NoReboot
        Write-Step "Waiting 120 seconds for Tools to install..."
        Start-Sleep -Seconds 120
        Write-OK "VMware Tools updated"
    } else {
        Write-OK "VMware Tools already up to date ($toolsStatus)"
    }
}
#endregion

#region ── 6. Run Windows Update ────────────────────────────────────────────
if (-not $SkipWindowsUpdate) {
    Write-Header "Windows Update"
    Write-Step "Installing PSWindowsUpdate module and applying updates..."

    # This script block runs INSIDE the VM guest via VMware Tools
    $updateScript = @'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Install-Module -Name PSWindowsUpdate -Force -Confirm:$false
        }
        Import-Module PSWindowsUpdate
        $updates = Get-WindowsUpdate -AcceptAll -Install -AutoReboot:$false -Verbose 2>&1
        $updates | Out-File C:\windows-update-log.txt
        Write-Output "Updates applied: $($updates.Count)"
'@

    Write-Step "Running Windows Update inside the VM (this may take 10-30 minutes)..."
    $result = Invoke-VMScript -VM $vm -ScriptType PowerShell -ScriptText $updateScript -GuestCredential $guestCred
    Write-OK "Windows Update result: $($result.ScriptOutput)"

    Write-Step "Rebooting VM to complete updates..."
    Restart-VMGuest -VM $vm -Confirm:$false | Out-Null
    Write-Step "Waiting 90 seconds for reboot..."
    Start-Sleep -Seconds 90

    # Wait for VMware Tools to come back online
    $timeout = 300; $elapsed = 0
    while ($elapsed -lt $timeout) {
        $currentVM = Get-VM -Name $VMName
        if ($currentVM.ExtensionData.Guest.ToolsStatus -eq 'toolsOk') { break }
        Start-Sleep -Seconds 10; $elapsed += 10
        Write-Step "Waiting for VM to come back online... ($elapsed/$timeout s)"
    }
    Write-OK "VM is back online after update reboot"
}
#endregion

#region ── 7. Sysprep ───────────────────────────────────────────────────────
Write-Header "Sysprep — Generalise the OS"
Write-Step "Running Sysprep inside the VM..."
Write-Warn "The VM will shut down automatically after Sysprep. This is expected."

# Sysprep with OOBE (Out-of-Box Experience) and Generalise flags
$sysprepScript = @'
    $sysprep = 'C:\Windows\System32\Sysprep\sysprep.exe'
    $args    = '/oobe /generalize /shutdown /quiet'
    Start-Process -FilePath $sysprep -ArgumentList $args -Wait
'@

$null = Invoke-VMScript -VM $vm -ScriptType PowerShell -ScriptText $sysprepScript -GuestCredential $guestCred

Write-Step "Sysprep started — waiting for VM to shut down..."
$timeout = 300; $elapsed = 0
while ($elapsed -lt $timeout) {
    $currentVM = Get-VM -Name $VMName
    if ($currentVM.PowerState -eq 'PoweredOff') {
        Write-OK "VM shut down cleanly after Sysprep"
        break
    }
    Start-Sleep -Seconds 10; $elapsed += 10
    Write-Step "Waiting for shutdown... ($elapsed/$timeout s)"
}

if ((Get-VM -Name $VMName).PowerState -ne 'PoweredOff') {
    Write-Fail "VM did not shut down within timeout. Check VM console for Sysprep errors."
}
#endregion

#region ── 8. Convert to template ──────────────────────────────────────────
Write-Header "Converting VM to Template"

if (-not $TemplateName) { $TemplateName = "$VMName-template" }

Write-Step "Converting '$VMName' to template '$TemplateName'..."
$vm | Set-VM -Name $TemplateName -Confirm:$false | Out-Null
Get-VM -Name $TemplateName | Set-VM -ToTemplate -Confirm:$false
Write-OK "Template '$TemplateName' created successfully"
#endregion

#region ── 9. Summary ───────────────────────────────────────────────────────
Write-Header "Template Ready"

$template = Get-Template -Name $TemplateName
Write-OK "Name       : $($template.Name)"
Write-OK "Guest OS   : $($template.Guest.OSFullName)"
Write-OK "vCPUs      : $($template.NumCpu)"
Write-OK "Memory     : $($template.MemoryGB) GB"

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Clone this template for each new server you need"
Write-Host "  2. Use clone-from-template.ps1 or the vCenter UI"
Write-Host "  3. On first boot, complete the Windows OOBE (set hostname, join domain)"
Write-Host "  4. Remember to update and re-seal the template every 30-90 days"
Write-Host ""

Disconnect-VIServer -Server $vCenterServer -Confirm:$false
#endregion
