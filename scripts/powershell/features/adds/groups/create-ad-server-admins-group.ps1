<#
.SYNOPSIS
This script automates the creation and configuration of server-specific Active Directory (AD) security groups for local admin privileges.

.DESCRIPTION
This PowerShell script simplifies the management of Active Directory by automatically configuring security groups tailored to each server. It checks if the server is a member of an AD domain, allows the Organizational Unit (OU) path to be passed as a variable with a default value, and then proceeds with the creation or update of specific local admin groups.

.PARAMETER OuPath
The Organizational Unit (OU) path where the group will be created. This parameter is optional and defaults to "OU=Server Local Admins,OU=Domain Groups".

.EXAMPLE
.\create-ad-server-admins-group.ps1
Executes the script using the current server's domain information and the default OU path to dynamically create or update the specific local admin group.

.EXAMPLE
.\create-ad-server-admins-group.ps1 -OuPath "OU=Custom OU,OU=Domain Groups,DC=example,DC=com"
Executes the script using a custom OU path for the creation or update of the specific local admin group.

.NOTES
Version: 1.1
Author: IT Surgery
Modification Date: 17-03-2024
#>

param(
    [string]$OuPath = "OU=Server Local Admins,OU=Domain Groups"
)

# Check if the computer is part of a domain
try {
    $domainCheck = (Get-WmiObject Win32_ComputerSystem).PartOfDomain
    if (-not $domainCheck) {
        Write-Warning "This server is not a member of any AD domain. Please join a domain before running this script."
        exit
    }
}
catch {
    Write-Error "Failed to determine the domain membership status. Error: $_"
    exit
}

# Get the FQDN of the domain the server is a member of
$fqdn = (Get-ADDomain).DNSRoot
$domainParts = $fqdn -split "\."
$DomainPrefix = $domainParts[0]
$DomainSuffix = $domainParts[1]

# Modify the default OU path with dynamic domain parts if not passed as a parameter
if ($OuPath -eq "OU=Server Local Admins,OU=Domain Groups") {
    $OuPath = "OU=Server Local Admins,OU=Domain Groups,DC=$DomainPrefix,DC=$DomainSuffix"
}

# Import the ActiveDirectory module without verbose output
Import-Module ActiveDirectory -Verbose:$false

# Construct the group name using the computer's name
$GroupName = "$ENV:COMPUTERNAME-Admins"

# Output a message indicating the creation of the server local admin group
Write-Output "Creating server local admin group $GroupName"

# Attempt to retrieve the AD group with the specified name
try {
    Get-ADGroup -Identity $GroupName -ErrorAction SilentlyContinue
}
catch {
    # If the group doesn't exist, create a new one
    New-ADGroup -Name $GroupName -Path $OuPath -GroupScope Global -GroupCategory Security -Description "AD Group To Delegate Local Admin Permissions To The Server $ENV:COMPUTERNAME"
}
