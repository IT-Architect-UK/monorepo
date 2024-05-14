<#
.SYNOPSIS
This script installs Active Directory Domain Services and creates a new Active Directory Forest.

.DESCRIPTION
The script installs the AD Domain Services role, configures DNS settings, sets up the PDC as an authoritative time server, and performs additional configurations for a new AD forest.

.NOTES
Version: 1.0
Author: IT Surgery
Modification Date: 08-03-2024

.PARAMETER AdDomainName
The desired Active Directory domain name. Default is "adds.private".

.PARAMETER AdNetbiosName
The NetBIOS name of the domain. Default is "ADDS".

.PARAMETER Password
The password for the Administrator account. Default is a pre-set complex password.

.EXAMPLE
.\[ScriptName].ps1 -AdDomainName "example.com" -AdNetbiosName "EXAMPLE" -Password "YourComplexPassword!"
#>

param(
    [string]$AdDomainName = "adds.private",
    [string]$AdNetbiosName = "ADDS",
    [string]$AdPassword = "C4ang3M3as@p01!"
)

# Function to write output to both console and log file
function Write-Log {
    param(
        [string]$Message
    )
    Write-Output $Message
    $Message | Out-File -FilePath $logPath -Append
}

# Determine log file location based on D:\ presence
$logDirectory = if (Test-Path 'D:\') { "D:\Logs\ADDS" } else { "C:\Logs\ADDS" }
if (-not (Test-Path $logDirectory)) {New-Item -ItemType Directory -Path $logDirectory -Force}
$currentDateTime = Get-Date -Format "yyyy-MM-dd-HH-mm-ss"
$logPath = "$logDirectory\ADDS-Forest-Install-$currentDateTime.log"

# Convert the plain text password to a secure string
$Credential = ConvertTo-SecureString $AdPassword -AsPlainText -Force

# Determine the installation drive based on availability
$AdDisk = if (Test-Path 'D:\') { "D:\" } else { "C:\" }
$AdDbPath = "${AdDisk}ADDS\Database"
$AdLogPath = "${AdDisk}ADDS\Log"
$AdSysvolPath = "${AdDisk}ADDS\SYSVOL"

Write-Log "Checking Active Directory Domain Services (ADDS) prerequisites."

# Check if the server is part of a domain
try {
    $currentDomain = Get-WmiObject Win32_ComputerSystem | Select-Object -ExpandProperty Domain
    if ($currentDomain -eq $AdDomainName) {
        Write-Log "The server is already a member of the domain '$AdDomainName'."
        $isDomainMember = $true
    } else {
        Write-Log "The server is not a member of the domain '$AdDomainName'."
        $isDomainMember = $false
    }
} catch {
    Write-Log "Failed to determine domain membership status. Assuming the server is not a member of any domain."
    $isDomainMember = $false
}

# Check if AD Domain Services role is installed
$adRole = Get-WindowsFeature -Name 'AD-Domain-Services'
if ($adRole.InstallState -eq 'Installed' -and $isDomainMember) {
    Write-Log "Active Directory Domain Services (ADDS) role is installed and the server is a member of a domain."
} else {
    Write-Log "Installing Active Directory Domain Services (ADDS)"
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
    Import-Module ADDSDeployment

    Install-ADDSForest `
        -CreateDnsDelegation:$false `
        -DatabasePath $AdDbPath `
        -DomainMode "7" `
        -DomainName $AdDomainName `
        -DomainNetbiosName $AdNetbiosName `
        -ForestMode "7" `
        -InstallDns:$true `
        -LogPath $AdLogPath `
        -NoRebootOnCompletion:$true `
        -SysvolPath $AdSysvolPath `
        -Force:$true `
        -SafeModeAdministratorPassword $Credential
    Write-Log "Active Directory Domain Services setup has initiated."
}

# Setting DNS suffix for all active network connections
Write-Log "Setting the DNS suffix for all active network connections to $AdDomainName"
$activeAdapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
foreach ($adapter in $activeAdapters) {
    Set-DnsClient -InterfaceIndex $adapter.ifIndex -ConnectionSpecificSuffix $AdDomainName
    Write-Log "Set DNS suffix for $($adapter.Name) to $AdDomainName."
}

# Configuring the PDC as an authoritative time server
$ntpKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters"
$ntpServersValue = "pool.ntp.org,0x9" # Modify as necessary
$configKeyPath = "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config"
$announceFlagsValue = 5 # PDC should be set to 5 to act as a reliable time source

Write-Log "Configuring the PDC as an authoritative time server"
Set-ItemProperty -Path $ntpKeyPath -Name "NtpServer" -Value $ntpServersValue
Set-ItemProperty -Path $ntpKeyPath -Name "Type" -Value ntp
Set-ItemProperty -Path $configKeyPath -Name "AnnounceFlags" -Value $announceFlagsValue
Set-Service -Name w32time -StartupType Automatic
Start-Service w32time

Write-Log "Active Directory Domain Services setup has completed."
Write-Log "Rebooting to complete ADDS installation."
Start-Sleep -Seconds 5
Restart-Computer