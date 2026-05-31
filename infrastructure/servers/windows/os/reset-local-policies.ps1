<#
.SYNOPSIS
    Resets all local Group Policy and security policy settings to Windows defaults.

.DESCRIPTION
    Removes the Group Policy and GroupPolicyUsers directories from System32,
    then forces a gpupdate to re-apply defaults. Used to clear misconfigured
    or conflicting local policies before applying a known-good GPO baseline.

    Optionally prompts to restart the computer after the reset.

.PARAMETER NoRestart
    Skip the restart prompt and do not restart.

.PARAMETER AutoRestart
    Restart automatically without prompting.

.EXAMPLE
    .\reset-local-policies.ps1
    # Resets policies and prompts to restart.

.EXAMPLE
    .\reset-local-policies.ps1 -AutoRestart
    # Resets policies and restarts automatically.

.NOTES
    Version:           1.1
    Author:            Darren Pilkington
    Modification Date: 31-05-2026
    Requires:          Local Administrator rights
#>

[CmdletBinding()]
param(
    [switch] $NoRestart,
    [switch] $AutoRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Logging ─────────────────────────────────────────────────────────────────
$LogDirectory = if (Test-Path 'D:\') { 'D:\Logs\PolicyReset' } else { 'C:\Logs\PolicyReset' }
if (-not (Test-Path $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
}
$LogFile = Join-Path $LogDirectory "reset-local-policies-$(Get-Date -Format 'yyyy-MM-dd-HH-mm-ss').log"

function Write-Log {
    param(
        [string] $Message,
        [ValidateSet('INFO','WARN','ERROR')] [string] $Level = 'INFO'
    )
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level]  $Message"
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

Write-Log "Local policy reset starting on $env:COMPUTERNAME."
Write-Log "Log file: $LogFile"

# ─── Pre-flight ──────────────────────────────────────────────────────────────
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Script must be run as Administrator." -Level ERROR
    exit 1
}

# ─── Remove GroupPolicyUsers directory ───────────────────────────────────────
$gpUsersPath = Join-Path $env:WinDir 'System32\GroupPolicyUsers'
if (Test-Path $gpUsersPath) {
    Write-Log "Removing GroupPolicyUsers directory: $gpUsersPath"
    Remove-Item -Path $gpUsersPath -Recurse -Force
    Write-Log "GroupPolicyUsers directory removed."
} else {
    Write-Log "GroupPolicyUsers directory not found — skipping."
}

# ─── Remove GroupPolicy directory ────────────────────────────────────────────
$gpPath = Join-Path $env:WinDir 'System32\GroupPolicy'
if (Test-Path $gpPath) {
    Write-Log "Removing GroupPolicy directory: $gpPath"
    Remove-Item -Path $gpPath -Recurse -Force
    Write-Log "GroupPolicy directory removed."
} else {
    Write-Log "GroupPolicy directory not found — skipping."
}

# ─── Force Group Policy update ────────────────────────────────────────────────
Write-Log "Running gpupdate /force to apply default policy settings..."
$gpResult = & gpupdate.exe /force 2>&1
Write-Log $gpResult
Write-Log "gpupdate completed."

# ─── Restart handling ────────────────────────────────────────────────────────
Write-Log "Local policy reset complete."
Write-Log "Log file: $LogFile"

if ($NoRestart) {
    Write-Log "Restart skipped (-NoRestart). Restart manually to fully apply defaults."
} elseif ($AutoRestart) {
    Write-Log "Auto-restarting in 10 seconds (-AutoRestart)..."
    Start-Sleep -Seconds 10
    Restart-Computer -Force
} else {
    $response = Read-Host "Restart the computer now to fully apply policy defaults? [Y/N]"
    if ($response -match '^[Yy]') {
        Write-Log "Restarting computer..."
        Restart-Computer -Force
    } else {
        Write-Log "Restart deferred. Restart manually when ready."
    }
}
