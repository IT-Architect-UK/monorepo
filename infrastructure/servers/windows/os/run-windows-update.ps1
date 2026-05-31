<#
.SYNOPSIS
    Installs all available Windows Updates and optionally reboots.

.DESCRIPTION
    Removes any WSUS group policy overrides so updates are sourced directly
    from Microsoft Update. Installs the PSWindowsUpdate module if not present.
    Downloads and installs all available updates, logs results, and optionally
    restarts the computer when complete.

.PARAMETER AutoReboot
    Restart the computer automatically if updates require it.

.PARAMETER NoAutoReboot
    Skip any automatic restart (default — you control when to reboot).

.EXAMPLE
    .\run-windows-update.ps1
    # Installs updates, no automatic reboot.

.EXAMPLE
    .\run-windows-update.ps1 -AutoReboot
    # Installs updates and reboots if required.

.NOTES
    Version:           1.1
    Author:            Darren Pilkington
    Modification Date: 31-05-2026
    Requires:          Local Administrator rights, internet access
#>

[CmdletBinding()]
param(
    [switch] $AutoReboot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Logging ─────────────────────────────────────────────────────────────────
$LogDirectory = if (Test-Path 'D:\') { 'D:\Logs\WindowsUpdate' } else { 'C:\Logs\WindowsUpdate' }
if (-not (Test-Path $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
}
$LogFile = Join-Path $LogDirectory "windows-update-$(Get-Date -Format 'yyyy-MM-dd-HH-mm-ss').log"

function Write-Log {
    param(
        [string] $Message,
        [ValidateSet('INFO','WARN','ERROR')] [string] $Level = 'INFO'
    )
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level]  $Message"
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

Write-Log "Windows Update script starting on $env:COMPUTERNAME."
Write-Log "Log file: $LogFile"

# ─── Pre-flight ──────────────────────────────────────────────────────────────
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Script must be run as Administrator." -Level ERROR
    exit 1
}

# ─── Remove WSUS policy overrides ────────────────────────────────────────────
Write-Log "Removing WSUS registry overrides to enable direct Microsoft Update..."
$wsusPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
if (Test-Path $wsusPath) {
    Remove-ItemProperty -Path $wsusPath -Name 'WUServer'       -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $wsusPath -Name 'WUStatusServer' -ErrorAction SilentlyContinue
    Write-Log "WSUS overrides removed."
} else {
    Write-Log "No WSUS policy keys found — skipping."
}

# ─── Restart Windows Update service ─────────────────────────────────────────
Write-Log "Restarting Windows Update service..."
Restart-Service -Name wuauserv -Force
Write-Log "Windows Update service restarted."

# ─── Install NuGet provider ───────────────────────────────────────────────────
Write-Log "Ensuring NuGet package provider is available..."
if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser | Out-Null
    Write-Log "NuGet provider installed."
} else {
    Write-Log "NuGet provider already installed."
}

# ─── Install PSWindowsUpdate module ──────────────────────────────────────────
Write-Log "Ensuring PSWindowsUpdate module is available..."
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Install-Module -Name PSWindowsUpdate -Force -Confirm:$false -Scope CurrentUser
    Write-Log "PSWindowsUpdate module installed."
} else {
    Write-Log "PSWindowsUpdate module already installed."
}

Import-Module PSWindowsUpdate -Force

# Register Microsoft Update service
Add-WUServiceManager -ServiceID '7971f918-a847-4430-9279-4a52d1efe18d' -Confirm:$false | Out-Null
Write-Log "Microsoft Update service registered."

# ─── Check for available updates ─────────────────────────────────────────────
Write-Log "Checking for available updates..."
$availableUpdates = Get-WindowsUpdate -MicrosoftUpdate -ErrorAction SilentlyContinue

if ($availableUpdates.Count -eq 0) {
    Write-Log "No updates available. System is up to date."
    exit 0
}

Write-Log "$($availableUpdates.Count) update(s) available:"
foreach ($update in $availableUpdates) {
    Write-Log "  - $($update.Title)"
}

# ─── Install updates ─────────────────────────────────────────────────────────
Write-Log "Installing updates..."
$installParams = @{
    MicrosoftUpdate = $true
    AcceptAll       = $true
    Confirm         = $false
    Install         = $true
}

if ($AutoReboot) {
    $installParams['AutoReboot'] = $true
    Write-Log "Auto-reboot enabled — server will restart automatically if required."
} else {
    $installParams['IgnoreReboot'] = $true
    Write-Log "Auto-reboot disabled — restart manually if required after updates complete."
}

$results = Get-WindowsUpdate @installParams

# ─── Log results ─────────────────────────────────────────────────────────────
if ($results) {
    Write-Log "Updates installed:"
    foreach ($result in $results) {
        Write-Log "  [$($result.ResultCode)] $($result.Title)"
    }
} else {
    Write-Log "No update results returned (updates may have installed silently)."
}

# ─── Check reboot requirement ────────────────────────────────────────────────
$rebootRequired = (Get-WURebootStatus -Silent -ErrorAction SilentlyContinue)
if ($rebootRequired) {
    if ($AutoReboot) {
        Write-Log "Reboot required. Restarting in 30 seconds..."
        Start-Sleep -Seconds 30
        Restart-Computer -Force
    } else {
        Write-Log "Reboot required to complete update installation. Run: Restart-Computer" -Level WARN
    }
} else {
    Write-Log "No reboot required."
}

Write-Log "Windows Update complete. Log: $LogFile"
