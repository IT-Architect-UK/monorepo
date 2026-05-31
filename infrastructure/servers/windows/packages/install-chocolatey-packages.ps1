<#
.SYNOPSIS
    Installs Chocolatey and a standard set of software packages.

.DESCRIPTION
    Checks for an active internet connection, installs Chocolatey if not
    present, then installs each package in the defined list. Skips packages
    that are already installed. Logs all actions.

    Default package list: git, notepadplusplus, powershell-core
    Edit the $ChocoPackages array below to customise.

.PARAMETER Packages
    Override the default package list with a custom array of Chocolatey
    package names.

.EXAMPLE
    .\install-chocolatey-packages.ps1

.EXAMPLE
    .\install-chocolatey-packages.ps1 -Packages @('git','7zip','vscode')

.NOTES
    Version:           1.2
    Author:            Darren Pilkington
    Modification Date: 31-05-2026
    Requires:          Local Administrator rights, internet access
#>

[CmdletBinding()]
param(
    [string[]] $Packages = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Logging ─────────────────────────────────────────────────────────────────
$LogDirectory = if (Test-Path 'D:\') { 'D:\Logs\Chocolatey' } else { 'C:\Logs\Chocolatey' }
if (-not (Test-Path $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
}
$LogFile = Join-Path $LogDirectory "install-chocolatey-$(Get-Date -Format 'yyyy-MM-dd-HH-mm-ss').log"

function Write-Log {
    param(
        [string] $Message,
        [ValidateSet('INFO','WARN','ERROR')] [string] $Level = 'INFO'
    )
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level]  $Message"
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

Write-Log "Chocolatey package installation starting on $env:COMPUTERNAME."
Write-Log "Log file: $LogFile"

# ─── Pre-flight ──────────────────────────────────────────────────────────────
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Script must be run as Administrator." -Level ERROR
    exit 1
}

# ─── Connectivity check ──────────────────────────────────────────────────────
Write-Log "Checking internet connectivity..."
if (-not (Test-Connection -ComputerName '8.8.8.8' -Count 2 -Quiet)) {
    Write-Log "No internet connectivity detected. Ensure the server has outbound access before running this script." -Level ERROR
    exit 1
}
Write-Log "Internet connectivity confirmed."

# ─── Package list ─────────────────────────────────────────────────────────────
# Default packages — edit this array or pass -Packages at runtime to override
$DefaultPackages = @(
    'git',
    'notepadplusplus',
    'powershell-core'
)

$ChocoPackages = if ($Packages.Count -gt 0) { $Packages } else { $DefaultPackages }
Write-Log "Packages to install: $($ChocoPackages -join ', ')"

# ─── Install Chocolatey ──────────────────────────────────────────────────────
if (Get-Command choco -ErrorAction SilentlyContinue) {
    Write-Log "Chocolatey is already installed: $(choco --version)"
} else {
    Write-Log "Installing Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = `
        [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

    $installScript = (Invoke-WebRequest -Uri 'https://community.chocolatey.org/install.ps1' `
        -UseBasicParsing).Content
    if ([string]::IsNullOrWhiteSpace($installScript)) {
        Write-Log "Failed to download Chocolatey installation script." -Level ERROR
        exit 1
    }
    Invoke-Expression $installScript

    # Reload PATH so 'choco' is available in this session
    $env:PATH = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('PATH', 'User')

    Write-Log "Chocolatey installed: $(choco --version)"
}

# ─── Install packages ────────────────────────────────────────────────────────
Write-Log "Installing packages..."
foreach ($package in $ChocoPackages) {
    try {
        # Check if already installed
        $installed = choco list --local-only --exact $package 2>$null |
                     Select-String -Pattern "^$package "
        if ($installed) {
            Write-Log "  $package : already installed — skipping."
        } else {
            Write-Log "  $package : installing..."
            choco install $package -y --no-progress | Out-Null
            Write-Log "  $package : installed successfully."
        }
    } catch {
        Write-Log "  $package : installation failed — $_" -Level WARN
    }
}

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Log "Package installation complete."
Write-Log "Installed packages:"
choco list --local-only 2>$null | ForEach-Object { Write-Log "  $_" }
Write-Log "Log file: $LogFile"
