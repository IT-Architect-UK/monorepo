<#
.SYNOPSIS
    Installs Active Directory Domain Services and promotes the server to a new forest root DC.

.DESCRIPTION
    Installs the AD-Domain-Services Windows feature, imports the ADDSDeployment module,
    and runs Install-ADDSForest to create a new AD forest. Also configures:
      - DNS suffix on all active network adapters
      - PDC as the authoritative NTP time source (W32Time)
    The server reboots automatically to complete the promotion.

.PARAMETER AdDomainName
    The fully qualified Active Directory domain name (e.g. corp.example.com).
    Default: adds.private

.PARAMETER AdNetbiosName
    The NetBIOS name for the domain (e.g. CORP). Default: ADDS

.PARAMETER SafeModePassword
    The Directory Services Restore Mode (DSRM) administrator password as a SecureString.
    This parameter is mandatory — no default value.

.PARAMETER NtpServer
    NTP server string for W32Time configuration on the PDC.
    Default: pool.ntp.org,0x9

.EXAMPLE
    $pwd = Read-Host -AsSecureString "Enter DSRM password"
    .\install-adds-new-forest.ps1 -AdDomainName "corp.example.com" -AdNetbiosName "CORP" -SafeModePassword $pwd

.NOTES
    Version:           1.2
    Author:            Darren Pilkington
    Modification Date: 31-05-2026
    Requires:          Windows Server 2019/2022, PowerShell 5.1+, local Administrator rights
#>

[CmdletBinding()]
param(
    [string]   $AdDomainName   = 'adds.private',
    [string]   $AdNetbiosName  = 'ADDS',
    [Parameter(Mandatory = $true)]
    [SecureString] $SafeModePassword,
    [string]   $NtpServer      = 'pool.ntp.org,0x9'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Logging ─────────────────────────────────────────────────────────────────
$LogDirectory = if (Test-Path 'D:\') { 'D:\Logs\ADDS' } else { 'C:\Logs\ADDS' }
if (-not (Test-Path $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
}
$LogFile = Join-Path $LogDirectory "ADDS-Forest-Install-$(Get-Date -Format 'yyyy-MM-dd-HH-mm-ss').log"

function Write-Log {
    param(
        [string] $Message,
        [ValidateSet('INFO','WARN','ERROR')] [string] $Level = 'INFO'
    )
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level]  $Message"
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

Write-Log "ADDS Forest installation starting."
Write-Log "  Domain name  : $AdDomainName"
Write-Log "  NetBIOS name : $AdNetbiosName"
Write-Log "  NTP server   : $NtpServer"
Write-Log "  Log file     : $LogFile"

# ─── Pre-flight checks ───────────────────────────────────────────────────────
Write-Log "Running pre-flight checks..."

# Require local administrator
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Script must be run as Administrator." -Level ERROR
    exit 1
}

# Check domain membership (use Get-CimInstance — WMI is deprecated)
try {
    $computerInfo = Get-CimInstance -ClassName Win32_ComputerSystem
    $isDomainMember = ($computerInfo.Domain -eq $AdDomainName)
    Write-Log "Current domain membership: $($computerInfo.Domain)"
} catch {
    Write-Log "Unable to determine domain membership: $_" -Level WARN
    $isDomainMember = $false
}

# ─── Install AD-Domain-Services role ─────────────────────────────────────────
$adRole = Get-WindowsFeature -Name 'AD-Domain-Services'

if ($adRole.InstallState -eq 'Installed' -and $isDomainMember) {
    Write-Log "ADDS role is already installed and server is a domain member — nothing to do."
} else {
    Write-Log "Installing AD-Domain-Services role with management tools..."
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools | Out-Null
    Write-Log "AD-Domain-Services role installed."

    Import-Module ADDSDeployment

    # Determine installation paths (prefer D:\ if available)
    $AdDisk     = if (Test-Path 'D:\') { 'D:\' } else { 'C:\' }
    $AdDbPath   = "${AdDisk}ADDS\Database"
    $AdLogPath  = "${AdDisk}ADDS\Log"
    $AdSysvolPath = "${AdDisk}ADDS\SYSVOL"

    Write-Log "Promoting server to domain controller for forest: $AdDomainName"
    Write-Log "  Database : $AdDbPath"
    Write-Log "  Log      : $AdLogPath"
    Write-Log "  SYSVOL   : $AdSysvolPath"

    Install-ADDSForest `
        -CreateDnsDelegation:$false `
        -DatabasePath        $AdDbPath `
        -DomainMode          'WinThreshold' `
        -DomainName          $AdDomainName `
        -DomainNetbiosName   $AdNetbiosName `
        -ForestMode          'WinThreshold' `
        -InstallDns:$true `
        -LogPath             $AdLogPath `
        -NoRebootOnCompletion:$true `
        -SysvolPath          $AdSysvolPath `
        -Force:$true `
        -SafeModeAdministratorPassword $SafeModePassword

    Write-Log "ADDS forest installation initiated."
}

# ─── Configure DNS suffix on all active adapters ─────────────────────────────
Write-Log "Configuring DNS search suffix '$AdDomainName' on active adapters..."
$activeAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
foreach ($adapter in $activeAdapters) {
    Set-DnsClient -InterfaceIndex $adapter.ifIndex -ConnectionSpecificSuffix $AdDomainName
    Write-Log "  Adapter '$($adapter.Name)': DNS suffix set to $AdDomainName"
}

# ─── Configure PDC as authoritative NTP source ───────────────────────────────
Write-Log "Configuring PDC as authoritative NTP time source..."
$ntpParamsPath  = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters'
$ntpConfigPath  = 'HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config'

Set-ItemProperty -Path $ntpParamsPath -Name 'NtpServer'      -Value $NtpServer
Set-ItemProperty -Path $ntpParamsPath -Name 'Type'           -Value 'NTP'
Set-ItemProperty -Path $ntpConfigPath -Name 'AnnounceFlags'  -Value 5

Set-Service  -Name w32time -StartupType Automatic
Restart-Service -Name w32time -Force
Write-Log "W32Time configured. NTP server: $NtpServer"

# ─── Reboot to complete promotion ────────────────────────────────────────────
Write-Log "ADDS setup complete. Rebooting in 10 seconds to finalise domain controller promotion..."
Start-Sleep -Seconds 10
Restart-Computer -Force
