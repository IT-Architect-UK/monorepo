<#
.SYNOPSIS
This script installs Chocolatey with Git, Notepad++, and PowerShell Core default packages.

.DESCRIPTION
The script performs the following actions:
- Checks for an active internet connection.
- Installs Chocolatey.
- Installs Git and adds it to the system PATH.
- Installs Notepad++.
- Installs PowerShell Core.
- Writes installation actions to a log file.

.NOTES
Version:        1.1
Author:         Darren Pilkington
Modification Date:  17-03-2024
#>

# Function to write output to both console and log file
function Write-Log {
    Param([string]$message)
    Write-Output $message
    Add-Content -Path $logPath -Value $message
}

Write-Output "Installing Chocolatey and Packages ...."
Write-Output "Configuring Script Log Settings."
# Determine log file path
$logDir = if (Test-Path D:\) { "D:\Logs\Chocolatey" } else { "C:\Logs\Chocolatey" }
$logFileName = "chocolatey-install-$(Get-Date -Format "yyyyMMdd-HHmmss").log"
$logPath = Join-Path -Path $logDir -ChildPath $logFileName
# Ensure log directory exists
if (-not (Test-Path $logDir)) {New-Item -Path $logDir -ItemType Directory}
Write-Log "Log file path set to $logPath."

# Check for active internet connection
$pingTest = Test-Connection 8.8.8.8 -Count 2 -Quiet
if (-not $pingTest) {
    Write-Host "No active internet connection found. Please ensure you are connected to the internet before running this script." -ForegroundColor Red
    Write-Log "No active internet connection found. Please ensure you are connected to the internet before running this script."
    exit
}
Write-Log "Active internet connection detected. Continuing with script ..."

Write-Log "Installing Chocolatey with Git, Notepad++, and PowerShell Core ..."

# Define a list of default packages to be installed
$chocoPackages = 'git', 'notepadplusplus', 'powershell-core'

Write-Log "Checking if Chocolatey is already installed. If not, install it."
if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Log "Installing Chocolatey ..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    $chocoInstallScript = (Invoke-WebRequest -Uri 'https://chocolatey.org/install.ps1' -UseBasicParsing).Content
    if ($chocoInstallScript) {
        Invoke-Expression $chocoInstallScript
    } else {Write-Log "Failed to download Chocolatey installation script."}
}

# Install each package
Write-Log "Installing Chocolatey Packages ..."
foreach ($package in $chocoPackages) {
    try {
        if (!(choco list --local-only | Select-String -Pattern $package)) {
            choco install $package -y --no-progress | Out-Null
            Write-Log "$package installed successfully."
        }
    } catch {
        Write-Output "$package is already installed or encountered an error."
        Write-Log "$package is already installed or encountered an error."
    }
}

Write-Log "Adding Git to PATH is handled within Chocolatey package installation scripts."
Write-Log "Installation complete. Please verify Git and other packages are correctly installed by running 'git --version', 'notepad++ --version', and 'pwsh --version'."
