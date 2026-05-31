param(
    [string]$AdminUser,
    [string]$AdminPassword
)

<#
.SYNOPSIS
This script creates a custom local admin user. This version of the script uses parameters:

> $AdminUser
> $AdminPassword

You can pass the username and password as switches when calling the script.
It checks if these parameters are provided; if not, it prompts the user to input them.

To run this script and pass the username and password as parameters, you would call it from the PowerShell command line like this:

```powershell
.\YourScriptName.ps1 -AdminUser "username" -AdminPassword "password"

.DESCRIPTION
The script performs the following actions:
- Optionally accepts a local admin username and password as command-line switches.
- Prompts for local admin username and password if not provided.
- Creates custom local admin user.

.NOTES
Version:        1.2
Author:         Darren Pilkington
Modification Date:  08-03-2024
#>

# Check if username was passed as a parameter, prompt if not.
if (-not $AdminUser) {
    $AdminUser = Read-Host "Enter the local admin username"
}

# Check if password was passed as a parameter, prompt if not.
if (-not $AdminPassword) {
    $plaintextPassword = Read-Host "Enter the local admin password" -AsSecureString
} else {
    $plaintextPassword = ConvertTo-SecureString -String $AdminPassword -AsPlainText -Force
}

# Convert the secure string password back to plain text. This is needed for 'net user' command.
$ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($plaintextPassword)
try {
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringUni($ptr)
}
finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeCoTaskMemUnicode($ptr)
}

# Output a message indicating the creation of the admin user if it doesn't exist and if the DC role is not installed.
Write-Output "Creating $AdminUser if the user does not exist & the DC role is not installed"

# Check if the 'AD-Domain-Services' role is installed on the server.
$domainControllerRole = Get-WindowsFeature 'AD-Domain-Services'

# If the role is installed, output a message indicating that the server is a domain controller and skip user creation.
if ($domainControllerRole.Installed) {
    Write-Output "Server is a domain controller; skipping user creation."
}
else {
    # If the role is not installed, proceed with user creation.
    Write-Output "Creating user $AdminUser"

    # Check if the user already exists on the system.
    try {
        $userExists = Get-LocalUser -Name $AdminUser -ErrorAction SilentlyContinue
    }
    catch {
        $userExists = $null
    }

    # If the user exists, output a message indicating so.
    if ($null -ne $userExists) {
        Write-Output "User $AdminUser already exists."
    }
    else {
        # If the user doesn't exist, create the user with the provided password and add them to the local administrators group.
        net user $AdminUser $password /add /y
        net localgroup administrators $AdminUser /add
        Write-Output "User $AdminUser created and added to the administrators group."
    }
}
