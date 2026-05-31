<#
.SYNOPSIS
    Renames the local computer and restarts it to apply the change.

.DESCRIPTION
    Renames the computer to a specified name or auto-generates a unique name
    using a timestamp suffix (format: SVRXXXXXXXXXX). The computer restarts
    automatically after rename unless -NoRestart is specified.

.PARAMETER NewComputerName
    The new computer name. If not provided, a unique name is auto-generated.

.PARAMETER NoRestart
    Skip the automatic restart after rename.

.EXAMPLE
    .\rename-computer.ps1 -NewComputerName "WEB-PROD-01"

.EXAMPLE
    .\rename-computer.ps1
    # Auto-generates a unique name and restarts.

.NOTES
    Version:           1.1
    Author:            Darren Pilkington
    Modification Date: 31-05-2026
    Requires:          Local Administrator rights
#>

[CmdletBinding()]
param(
    [string] $NewComputerName = '',
    [switch] $NoRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Logging ─────────────────────────────────────────────────────────────────
$LogDirectory = if (Test-Path 'D:\') { 'D:\Logs\OS' } else { 'C:\Logs\OS' }
if (-not (Test-Path $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
}
$LogFile = Join-Path $LogDirectory "rename-computer-$(Get-Date -Format 'yyyy-MM-dd-HH-mm-ss').log"

function Write-Log {
    param(
        [string] $Message,
        [ValidateSet('INFO','WARN','ERROR')] [string] $Level = 'INFO'
    )
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level]  $Message"
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

Write-Log "Rename computer script starting."
Write-Log "Log file: $LogFile"

# ─── Pre-flight ──────────────────────────────────────────────────────────────
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Script must be run as Administrator." -Level ERROR
    exit 1
}

# ─── Determine new name ──────────────────────────────────────────────────────
if ([string]::IsNullOrWhiteSpace($NewComputerName)) {
    # Generate a unique name from a Unix-epoch timestamp (last 8 digits)
    $timestamp  = [int64](Get-Date -UFormat %s) % 100000000
    $NewComputerName = "SVR$timestamp"
    Write-Log "No name provided — auto-generated: $NewComputerName"
} else {
    Write-Log "New computer name specified: $NewComputerName"
}

# Validate name length (NetBIOS limit: 15 chars)
if ($NewComputerName.Length -gt 15) {
    Write-Log "Computer name '$NewComputerName' exceeds 15 characters." -Level ERROR
    exit 1
}

$currentName = $env:COMPUTERNAME
Write-Log "Current computer name: $currentName"

if ($currentName -eq $NewComputerName) {
    Write-Log "Computer is already named '$NewComputerName' — nothing to do."
    exit 0
}

# ─── Rename ───────────────────────────────────────────────────────────────────
Write-Log "Renaming computer from '$currentName' to '$NewComputerName'..."
Rename-Computer -NewName $NewComputerName -Force
Write-Log "Computer renamed successfully."

# ─── Restart ─────────────────────────────────────────────────────────────────
if ($NoRestart) {
    Write-Log "Restart skipped (-NoRestart). Restart manually to apply the new name."
} else {
    Write-Log "Restarting in 5 seconds to apply the new computer name..."
    Start-Sleep -Seconds 5
    Restart-Computer -Force
}
