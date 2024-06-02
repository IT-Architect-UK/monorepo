param(
    [string]$AdminUser,
    [string]$AdminPassword
)

<#
.SYNOPSIS
This script installs the Windows Exporter for Prometheus monitoring.

.DESCRIPTION
The script performs the following actions:
- Checks if the current user is an administrator.
- Optionally accepts a local admin username and password as command-line switches.
- Prompts for local admin username and password if the current user is not an administrator.
- Downloads the Windows Exporter MSI installer.
- Installs the Windows Exporter.
- Starts the Windows Exporter service.

.NOTES
Version:        1.0
Author:         ChatGPT
Modification Date:  02-06-2024
#>

# Function to check if the current user is an administrator
function Test-IsAdmin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Check if the current user is an administrator
if (Test-IsAdmin) {
    Write-Host "Current user is an administrator. No credentials are required."
} else {
    Write-Host "Current user is not an administrator. Admin credentials are required."
    # Check if AdminUser and AdminPassword parameters are provided
    if (-not $AdminUser) {
        $AdminUser = Read-Host -Prompt 'Enter the admin username'
    }
    if (-not $AdminPassword) {
        $AdminPassword = Read-Host -Prompt 'Enter the admin password' -AsSecureString
    }
}

# Download Windows Exporter
Invoke-WebRequest -Uri "https://github.com/prometheus-community/windows_exporter/releases/download/v0.16.0/windows_exporter-0.16.0-amd64.msi" -OutFile "windows_exporter.msi"

# Install Windows Exporter
if (Test-IsAdmin) {
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i windows_exporter.msi /quiet" -Wait
} else {
    Start-Process -FilePath "msiexec.exe" -ArgumentList "/i windows_exporter.msi /quiet" -Wait -Credential (New-Object System.Management.Automation.PSCredential($AdminUser, $AdminPassword))
}

# Start Windows Exporter Service
Start-Service -Name "windows_exporter"
