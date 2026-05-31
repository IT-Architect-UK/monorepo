<#
.SYNOPSIS
    Creates a local administrator account on the server.

.DESCRIPTION
    Creates a local user account and adds it to the local Administrators group.
    Skips creation if the user already exists. Skips on Domain Controllers
    where local user management is not applicable.
    The password is always passed as a SecureString — it is never stored in
    plain text or written to the log.

.PARAMETER AdminUser
    Username for the new local administrator account. Prompted if not supplied.

.PARAMETER AdminPassword
    Password as a SecureString. Prompted securely if not supplied.

.EXAMPLE
    .\create-local-admin.ps1 -AdminUser "localadmin"
    # Prompts for password securely at runtime.

.EXAMPLE
    $pwd = Read-Host -AsSecureString "Password"
    .\create-local-admin.ps1 -AdminUser "localadmin" -AdminPassword $pwd

.NOTES
    Version:           1.2
    Author:            Darren Pilkington
    Modification Date: 31-05-2026
    Requires:          Local Administrator rights (not applicable on Domain Controllers)
#>

[CmdletBinding()]
param(
    [string]      $AdminUser     = '',
    [SecureString] $AdminPassword = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Logging ─────────────────────────────────────────────────────────────────
$LogDirectory = if (Test-Path 'D:\') { 'D:\Logs\UserManagement' } else { 'C:\Logs\UserManagement' }
if (-not (Test-Path $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
}
$LogFile = Join-Path $LogDirectory "create-local-admin-$(Get-Date -Format 'yyyy-MM-dd-HH-mm-ss').log"

function Write-Log {
    param(
        [string] $Message,
        [ValidateSet('INFO','WARN','ERROR')] [string] $Level = 'INFO'
    )
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level]  $Message"
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

Write-Log "Create local admin script starting on $env:COMPUTERNAME."
Write-Log "Log file: $LogFile"

# ─── Pre-flight ──────────────────────────────────────────────────────────────
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Script must be run as Administrator." -Level ERROR
    exit 1
}

# Skip on Domain Controllers
$dcRole = Get-WindowsFeature -Name 'AD-Domain-Services' -ErrorAction SilentlyContinue
if ($dcRole -and $dcRole.Installed) {
    Write-Log "This server is a Domain Controller — local user management is not applicable." -Level WARN
    Write-Log "Manage users via Active Directory Users and Computers or PowerShell AD cmdlets."
    exit 0
}

# ─── Prompt for missing parameters ───────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($AdminUser)) {
    $AdminUser = Read-Host "Enter the local admin username"
}
if ($null -eq $AdminPassword) {
    $AdminPassword = Read-Host "Enter the local admin password" -AsSecureString
}

Write-Log "Target username: $AdminUser"

# ─── Check if user already exists ────────────────────────────────────────────
$existingUser = Get-LocalUser -Name $AdminUser -ErrorAction SilentlyContinue
if ($existingUser) {
    Write-Log "User '$AdminUser' already exists — skipping creation." -Level WARN
} else {
    # ─── Create the user ─────────────────────────────────────────────────────
    Write-Log "Creating local user '$AdminUser'..."
    New-LocalUser `
        -Name                 $AdminUser `
        -Password             $AdminPassword `
        -PasswordNeverExpires:$false `
        -AccountNeverExpires `
        -Description          "Local administrator — managed by create-local-admin.ps1" | Out-Null
    Write-Log "User '$AdminUser' created."
}

# ─── Add to local Administrators group ───────────────────────────────────────
$adminsGroup = Get-LocalGroup -Name 'Administrators' -ErrorAction SilentlyContinue
if ($adminsGroup) {
    $isMember = Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "\\$AdminUser$" -or $_.Name -eq $AdminUser }
    if ($isMember) {
        Write-Log "User '$AdminUser' is already in the Administrators group."
    } else {
        Add-LocalGroupMember -Group 'Administrators' -Member $AdminUser
        Write-Log "User '$AdminUser' added to the Administrators group."
    }
} else {
    Write-Log "Could not find the Administrators group." -Level ERROR
    exit 1
}

Write-Log "Local admin account setup complete."
Write-Log "  Username : $AdminUser"
Write-Log "  Groups   : Administrators"
Write-Log "  Log file : $LogFile"
