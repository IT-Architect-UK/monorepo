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

Write-Output "Creating Baseline AD OU Objects"

# Pre-execution checks
# Check if the script is running on a domain member server
try {
    $domainCheck = Get-WmiObject Win32_ComputerSystem
    if ($domainCheck.PartOfDomain -eq $false) {
        Write-Error "This script requires the server it's running on to be a domain member."
        exit
    }
} catch {
    Write-Error "Failed to determine if the server is a domain member. Ensure you have the necessary permissions to perform this check."
    exit
}
# Check if the user is a domain admin
try {
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $domainAdminGroupSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-21domain-512")
    $domainAdmins = [System.Security.Principal.WindowsPrincipal]::new([System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole($domainAdminGroupSID)
    if (-not $domainAdmins) {
        Write-Error "The user running this script must be a domain admin."
        exit
    }
} catch {
    Write-Error "Failed to verify if the current user is a domain admin. Ensure you have the necessary permissions to perform this check."
    exit
}

Import-Module ActiveDirectory

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
