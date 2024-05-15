<#
.SYNOPSIS
This script configures a new Active Directory environment, including dynamic site and subnet creation, enabling the AD Recycle Bin, renaming the default site, creating organizational units (OUs), and setting up essential AD groups.

.DESCRIPTION
This comprehensive PowerShell script automates the initial setup and configuration of a new Active Directory (AD) environment. Key features include:
- Dynamically determining and configuring the subnet IP and mask for a new AD site based on the server's primary IPv4 address.
- Enabling the AD Recycle Bin for enhanced object recovery.
- Renaming the default site and associating it with the dynamically determined subnet.
- Creating a structured OU hierarchy to organize domain resources effectively.
- Establishing essential AD security groups for administrative roles and permissions.

The script is designed to provide a solid foundation for a new AD deployment, ensuring critical configurations are in place and organized systematically.

.PARAMETER NewSiteName
Specifies the name for the new AD site. Default is "ADDS-Site-1".

.PARAMETER AdminUser
Specifies the administrator username to be used in various configurations. Default is "Administrator".

.EXAMPLE
.\ThisScriptName.ps1
Runs the script with default parameters for NewSiteName ("ADDS-Site-1") and AdminUser ("Administrator").

.EXAMPLE
.\ThisScriptName.ps1 -NewSiteName "CustomSiteName" -AdminUser "CustomAdmin"
Runs the script with custom values for the NewSiteName and AdminUser parameters. Replace "CustomSiteName" with your desired site name and "CustomAdmin" with your specific admin username.

.NOTES
Version: 1.0
Author: IT Surgery
Modification Date: 08-03-2024

#>

# Variables
param(
    [string]$NewSiteName = "ADDS-Site-1",
    [string]$AdminUser = "Administrator"
)

# Dynamically determine subnet IP and mask for new site based on server's primary IPv4 address
$ipconfig = Get-NetIPAddress -AddressFamily IPv4 -PrefixOrigin Dhcp, Manual | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } | Select-Object -First 1
$subnetMaskLength = $ipconfig.PrefixLength
$ipAddress = $ipconfig.IPAddress
# Simplify subnet calculation to ensure correctness
function ConvertTo-Binary {
    param (
        [int]$decimal
    )
    $binary = [convert]::ToString($decimal, 2)
    return $binary.PadLeft(8, '0')
}
$ipBinary = ($ipAddress -split "\." | ForEach-Object { ConvertTo-Binary -decimal $_ }) -join ""
$subnetBinary = $ipBinary.Substring(0, $subnetMaskLength).PadRight(32, '0')
$subnetAddressBytes = @()
for ($i = 0; $i -lt 32; $i += 8) {
    $byte = $subnetBinary.Substring($i, 8)
    $subnetAddressBytes += [convert]::ToInt32($byte, 2)
}
$subnetAddress = $subnetAddressBytes -join "."
$NewSiteSubnet = "$subnetAddress/$subnetMaskLength"
Write-Output "Detected Subnet for New Site: $NewSiteSubnet"

Write-Output "Creating Baseline AD Objects"
Import-Module ActiveDirectory

Write-Output "Enabling AD Recycle Bin"
function IsADRecycleBinEnabled {
    $adForest = Get-ADForest
    Write-Output "Recycle Bin Enabled status: $($adForest.RecycleBinEnabled)"
    return $adForest.RecycleBinEnabled
}

# Directly use the function in the if-statement to check its return value
if (IsADRecycleBinEnabled -eq $true) {
    Write-Output "AD Recycle Bin is already enabled."
} else {
    try {
        # Enable the AD Recycle Bin without confirmation prompt
        Enable-ADOptionalFeature 'Recycle Bin Feature' `
            -Scope ForestOrConfigurationSet `
            -Target (Get-ADForest).Name `
            -Confirm:$false
        Write-Output "AD Recycle Bin has been successfully enabled."
    } catch {
        Write-Output "An attempt was made to enable AD Recycle Bin, but it failed with the following error: $_"
    }
}

Write-Output "Renaming Default-First-Site-Name to $NewSiteName"
# Check and rename the site if necessary
$oldSiteName = "Default-First-Site-Name"
try {
    $site = Get-ADReplicationSite -Identity $oldSiteName -ErrorAction Stop
    Rename-ADObject -Identity $site.DistinguishedName -NewName $NewSiteName
    Write-Output "Site name changed from $oldSiteName to $NewSiteName"
} catch {
    Write-Output "Site $oldSiteName has already been renamed or does not exist."
}

# Define and associate the subnets with the site
try {
    Get-ADReplicationSubnet -Identity $NewSiteSubnet -ErrorAction Stop
    Write-Output "Subnet $NewSiteSubnet already exists."
} catch {
    New-ADReplicationSubnet -Name $NewSiteSubnet -Site $NewSiteName -Location "$NewSiteName"
    Write-Output "Subnet $NewSiteSubnet associated with site $NewSiteName"
}

# Get the FQDN of the domain the server is a member of
$fqdn = (Get-ADDomain).DNSRoot
$domainParts = $fqdn -split "\."
$DomainPrefix = $domainParts[0]
$DomainSuffix = $domainParts[1]

Write-Output "Creating OUs"
$ouName = "Domain Groups"
$ou = Try {Get-ADOrganizationalUnit -Filter { Name -eq $ouName }} Catch {$null}
if ($null -eq $ou) {
    New-ADOrganizationalUnit -Name $ouName -Path "DC=$DomainPrefix,DC=$DomainSuffix"
} else {Write-Output "OU $ouName already exists."}
$ouName = "Application Groups"
$ou = Try {Get-ADOrganizationalUnit -Filter { Name -eq $ouName }} Catch {$null}
if ($null -eq $ou) {
    New-ADOrganizationalUnit -Name $ouName -Path "OU=Domain Groups,DC=$DomainPrefix,DC=$DomainSuffix"
} else {Write-Output "OU $ouName already exists."}
$ouName = "Server Local Admins"
$ou = Try {Get-ADOrganizationalUnit -Filter { Name -eq $ouName }} Catch {$null}
if ($null -eq $ou) {
    New-ADOrganizationalUnit -Name $ouName -Path "OU=Domain Groups,DC=$DomainPrefix,DC=$DomainSuffix"
} else {Write-Output "OU $ouName already exists."}
$ouName = "AD-ActiveDirectory-Groups"
$ou = Try {Get-ADOrganizationalUnit -Filter { Name -eq $ouName }} Catch {$null}
if ($null -eq $ou) {
    New-ADOrganizationalUnit -Name $ouName -Path "OU=Application Groups,OU=Domain Groups,DC=$DomainPrefix,DC=$DomainSuffix"
} else {Write-Output "OU $ouName already exists."}
$ouName = "Domain Servers"
$ou = Try {Get-ADOrganizationalUnit -Filter { Name -eq $ouName }} Catch {$null}
if ($null -eq $ou) {
    New-ADOrganizationalUnit -Name $ouName -Path "DC=$DomainPrefix,DC=$DomainSuffix"
} else {Write-Output "OU $ouName already exists."}
$ouName = "AD-ActiveDirectory-Servers"
$ou = Try {Get-ADOrganizationalUnit -Filter { Name -eq $ouName }} Catch {$null}
if ($null -eq $ou) {
    New-ADOrganizationalUnit -Name $ouName -Path "OU=Domain Servers,DC=$DomainPrefix,DC=$DomainSuffix"
} else {Write-Output "OU $ouName already exists."}
$ouName = "Domain Users"
$ou = Try {Get-ADOrganizationalUnit -Filter { Name -eq $ouName }} Catch {$null}
if ($null -eq $ou) {
    New-ADOrganizationalUnit -Name $ouName -Path "DC=$DomainPrefix,DC=$DomainSuffix"
} else {Write-Output "OU $ouName already exists."}
$ouName = "Privileged Users"
$ou = Try {Get-ADOrganizationalUnit -Filter { Name -eq $ouName }} Catch {$null}
if ($null -eq $ou) {
    New-ADOrganizationalUnit -Name $ouName -Path "OU=Domain Users,DC=$DomainPrefix,DC=$DomainSuffix"
} else {Write-Output "OU $ouName already exists."}
$ouName = "Non-Privileged Users"
$ou = Try {Get-ADOrganizationalUnit -Filter { Name -eq $ouName }} Catch {$null}
if ($null -eq $ou) {
    New-ADOrganizationalUnit -Name $ouName -Path "OU=Domain Users,DC=$DomainPrefix,DC=$DomainSuffix"
} else {Write-Output "OU $ouName already exists."}
$ouName = "Service Accounts"
$ou = Try {Get-ADOrganizationalUnit -Filter { Name -eq $ouName }} Catch {$null}
if ($null -eq $ou) {
    New-ADOrganizationalUnit -Name $ouName -Path "OU=Domain Users,DC=$DomainPrefix,DC=$DomainSuffix"
} else {Write-Output "OU $ouName already exists."}
$ouName = "IDM Groups"
$ou = Try {Get-ADOrganizationalUnit -Filter { Name -eq $ouName }} Catch {$null}
if ($null -eq $ou) {
    New-ADOrganizationalUnit -Name $ouName -Path "DC=$DomainPrefix,DC=$DomainSuffix"
} else {Write-Output "OU $ouName already exists."}
$ouName = "IDM Host Groups"
$ou = Try {Get-ADOrganizationalUnit -Filter { Name -eq $ouName }} Catch {$null}
if ($null -eq $ou) {
    New-ADOrganizationalUnit -Name $ouName -Path "OU=IDM Groups,DC=$DomainPrefix,DC=$DomainSuffix"
} else {Write-Output "OU $ouName already exists."}
$ouName = "IDM Server Local Admins"
$ou = Try {Get-ADOrganizationalUnit -Filter { Name -eq $ouName }} Catch {$null}
if ($null -eq $ou) {
    New-ADOrganizationalUnit -Name $ouName -Path "OU=IDM Groups,DC=$DomainPrefix,DC=$DomainSuffix"
} else {Write-Output "OU $ouName already exists."}

Write-Output "Creating Block All GPOs OU and blocking GPO inheritance"
$ouName = "Block All GPOs"
$ouPath = "OU=Domain Servers,DC=$DomainPrefix,DC=$DomainSuffix"
$ou = Try {Get-ADOrganizationalUnit -Filter { Name -eq $ouName }} Catch {$null}
if ($null -eq $ou) {
    $ou = New-ADOrganizationalUnit -Name $ouName -Path $ouPath
    Write-Output "The $ouName OU has been created ..."
    $retryCount = 0
    $maxRetries = 60
    $retryInterval = 10 # seconds
    do {
        Start-Sleep -Seconds $retryInterval
        $ou = Try {Get-ADOrganizationalUnit -Filter { Name -eq $ouName }} Catch {$null}
        $retryCount++
    } while ($null -eq $ou.DistinguishedName -and $retryCount -lt $maxRetries)
    if ($null -eq $ou.DistinguishedName) {
        Write-Output "Failed to retrieve the OU after $maxRetries attempts."
        return}
    Write-Output "Blocking GPO inheritance for $ouName ..."
    Set-GPInheritance -Target $ou.DistinguishedName -IsBlocked Yes} else {
    Write-Output "OU $ouName already exists."
    Write-Output "Checking if GPO inheritance is already blocked ..."
    $inheritance = Get-GPInheritance -Target $ou.DistinguishedName
    Write-Output "Blocked Inheritance Value Is $($inheritance.GpoInheritanceBlocked)"
    if ($inheritance.GpoInheritanceBlocked -ne "Yes") {
        Set-GPInheritance -Target $ou.DistinguishedName -IsBlocked Yes
        Write-Output "GPO inheritance blocked for $ouName."
    } else {Write-Output "GPO inheritance is already blocked for $ouName."}
}

Write-Output "Creating Default Computer Staging OU"
$ouName = "Staging"
$ouPath = "OU=Domain Servers,DC=$DomainPrefix,DC=$DomainSuffix"
$fullOuPath = "OU=$ouName,$ouPath"
$ou = Try {Get-ADOrganizationalUnit -Filter { Name -eq $ouName }} Catch {$null}
if ($null -eq $ou) {
    New-ADOrganizationalUnit -Name $ouName -Path $ouPath
    Write-Output "OU $ouName created."
} else {Write-Output "OU $ouName already exists."}
Write-Output "Redirecting default computer container to the Staging OU ..."
# Retrieve the current default location for new computer objects
$currentContainer = (Get-ADDomain).ComputersContainer
Write-Output "Current default computer container is $currentContainer."
# Check if the current container matches the desired container
if ($currentContainer -ne $fullOuPath) {
    redircmp $fullOuPath
    Write-Output "Default computer container redirected to $fullOuPath."
} else {Write-Output "Default computer container is already set to $fullOuPath."}

Write-Output "Creating AD Groups"
$OuPath = "OU=AD-ActiveDirectory-Groups,OU=Application Groups,OU=Domain Groups,DC=$DomainPrefix,DC=$DomainSuffix"
$GroupName = "SVR-Deny-Interactive-Logon"
Write-Output "Creating group $GroupName"
try {Get-ADGroup -Identity $GroupName -ErrorAction SilentlyContinue}
catch {New-ADGroup -Name $GroupName -Path $OuPath -GroupScope Global -GroupCategory Security -Description "AD User objects that cannot logon via RDP or Locally"}
$GroupName = "SVR-Allow-Logon-As-A-Service"
Write-Output "Creating group $GroupName"
try {Get-ADGroup -Identity $GroupName -ErrorAction SilentlyContinue}
catch {New-ADGroup -Name $GroupName -Path $OuPath -GroupScope Global -GroupCategory Security -Description "AD User objects allowed to run as a service"}
$GroupName = "SVR-Application-Service-Accounts"
Write-Output "Creating group $GroupName"
try {Get-ADGroup -Identity $GroupName -ErrorAction SilentlyContinue}
catch {New-ADGroup -Name $GroupName -Path $OuPath -GroupScope Global -GroupCategory Security -Description "Application Service Accounts (Non Microsoft AD Managed) )"}
$existingGroups = @("SVR-Deny-Interactive-Logon", "SVR-Allow-Logon-As-A-Service")
foreach ($group in $existingGroups) {try {
        Write-Output "Adding $GroupName to $group"
        Add-ADGroupMember -Identity $group -Members $GroupName}
    catch {Write-Output "Error adding $GroupName to ${group}: $_"}
}
$GroupName = "SVR-Allow-Logon-As-A-Batch"
Write-Output "Creating group $GroupName"
try {Get-ADGroup -Identity $GroupName -ErrorAction SilentlyContinue}
catch {New-ADGroup -Name $GroupName -Path $OuPath -GroupScope Global -GroupCategory Security -Description "AD User objects allowed to run a batch job"}
$GroupName = "SVR-Allow-Run-A-Scheduled-Task"
Write-Output "Creating group $GroupName"
try {Get-ADGroup -Identity $GroupName -ErrorAction SilentlyContinue}
catch {New-ADGroup -Name $GroupName -Path $OuPath -GroupScope Global -GroupCategory Security -Description "AD User objects allowed to run a scheduled task with cached credentials"}
$GroupName = "SVR-Disable-Strict-Passwords"
Write-Output "Creating group $GroupName"
try {Get-ADGroup -Identity $GroupName -ErrorAction SilentlyContinue}
catch {New-ADGroup -Name $GroupName -Path $OuPath -GroupScope Global -GroupCategory Security -Description "AD User objects with strict password requirements disabled"}
$GroupName = "RBAG-AD-Admins"
Write-Output "Creating group $GroupName"
try {Get-ADGroup -Identity $GroupName -ErrorAction SilentlyContinue}
catch {New-ADGroup -Name $GroupName -Path $OuPath -GroupScope Global -GroupCategory Security -Description "AD Administrators with change access to all AD services and objects"}
$GroupName = "RBAG-AD-Operations"
Write-Output "Creating group $GroupName"
try {Get-ADGroup -Identity $GroupName -ErrorAction SilentlyContinue}
catch {New-ADGroup -Name $GroupName -Path $OuPath -GroupScope Global -GroupCategory Security -Description "AD Administrators with privileged access to AD tools & services"}
$GroupName = "RBAG-AD-User-Admins"
Write-Output "Creating group $GroupName"
try {Get-ADGroup -Identity $GroupName -ErrorAction SilentlyContinue}
catch {New-ADGroup -Name $GroupName -Path $OuPath -GroupScope Global -GroupCategory Security -Description "Administrators that can unlock and reset user password"}
$GroupName = "RBAG-SVR-Admin"
Write-Output "Creating group $GroupName"
try {Get-ADGroup -Identity $GroupName -ErrorAction SilentlyContinue}
catch {New-ADGroup -Name $GroupName -Path $OuPath -GroupScope Global -GroupCategory Security -Description "Server administrators that can manage all servers and AD tooling"}

Write-Output "Adding $AdminUser to AD Group: RBAG-SVR-Admin"
$group = "RBAG-SVR-Admin"
try {
    $isMember = Get-ADGroupMember -Identity $group | Where-Object { $_.SamAccountName -eq "$AdminUser" }
    if ($isMember) {
        Write-Output "User $DomainNetbiosName\$AdminUser is already a member of the group $group"
    } else {
        Add-ADGroupMember -Identity $group -Members "$AdminUser" -ErrorAction Continue
        Write-Output "Added $AdminUser to $group"
    }
} catch {Write-Output "An error occurred while processing $AdminUser for ${group}: $_"}
