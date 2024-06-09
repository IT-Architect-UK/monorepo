<#
.SYNOPSIS
This script installs the latest Zabbix agent v2 on a Windows operating system using Chocolatey.

.DESCRIPTION
The script performs the following actions:
- Checks for an active internet connection.
- Installs Chocolatey if not already installed.
- Installs or upgrades the Zabbix Agent v2 using Chocolatey.
- Verifies the installation and ensures the service is running and the TCP port is listening.
- Writes installation actions to a log file.

.PARAMETER ServerIP
The IP address of the Zabbix server.

.PARAMETER ServerName
The name of the Zabbix server.

.EXAMPLE
.\Install-ZabbixAgent.ps1 -ServerIP "192.168.1.1" -ServerName "ZABBIX-SERVER.example.com"

.NOTES
Version:        1.0
Author:         Darren Pilkington
Modification Date:  09-06-2024
#>

param (
    [string]$ServerIP,
    [string]$ServerName
)

# Function to write output to both console and log file
function Write-Log {
    Param([string]$message)
    Write-Output $message
    Add-Content -Path $logPath -Value $message
}

# Prompt for Server IP if not provided
if (-not $ServerIP) {
    $ServerIP = Read-Host -Prompt "Please enter the Zabbix server IP address"
}

# Prompt for Server Name if not provided
if (-not $ServerName) {
    $ServerName = Read-Host -Prompt "Please enter the Zabbix server name"
}

Write-Output "Installing Zabbix Agent v2 ...."
Write-Output "Configuring Script Log Settings."
# Determine log file path
$logDir = if (Test-Path D:\) { "D:\Logs\Zabbix" } else { "C:\Logs\Zabbix" }
$logFileName = "zabbix-install-$(Get-Date -Format "yyyyMMdd-HHmmss").log"
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

# Check if Chocolatey is installed, if not install it
Write-Log "Checking if Chocolatey is already installed. If not, install it."
if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Log "Installing Chocolatey ..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    $chocoInstallScript = (Invoke-WebRequest -Uri 'https://chocolatey.org/install.ps1' -UseBasicParsing).Content
    if ($chocoInstallScript) {
        Invoke-Expression $chocoInstallScript
        Write-Log "Chocolatey installed successfully."
    } else {
        Write-Log "Failed to download Chocolatey installation script."
        exit
    }
} else {
    Write-Log "Chocolatey is already installed."
}

# Function to install or upgrade Zabbix Agent v2
function Install-ZabbixAgent {
    Param([string]$installCommand)

    Write-Log "Executing: $installCommand"
    Invoke-Expression $installCommand
    $exitCode = $LASTEXITCODE

    if ($exitCode -eq 0) {
        Write-Log "Chocolatey command executed successfully."
    } else {
        Write-Log "Chocolatey command failed with exit code $exitCode."
        exit
    }
}

# Install or upgrade Zabbix Agent v2 using Chocolatey
Write-Log "Installing Zabbix Agent v2 using Chocolatey ..."
try {
    if (!(choco list --local-only | Select-String -Pattern "zabbix-agent2")) {
        $installCommand = "choco install zabbix-agent2 -y --no-progress --params '/SERVER:$ServerIP /SERVERACTIVE:$ServerName /HOSTNAME:$env:COMPUTERNAME'"
        Install-ZabbixAgent -installCommand $installCommand
        Write-Log "Zabbix Agent v2 installed successfully."
    } else {
        Write-Log "Zabbix Agent v2 is already installed. Upgrading..."
        $upgradeCommand = "choco upgrade zabbix-agent2 -y --no-progress --params '/SERVER:$ServerIP /SERVERACTIVE:$ServerName /HOSTNAME:$env:COMPUTERNAME'"
        Install-ZabbixAgent -installCommand $upgradeCommand
        Write-Log "Zabbix Agent v2 upgraded successfully."
    }
} catch {
    Write-Host "Failed to install or upgrade Zabbix Agent v2. Exiting script." -ForegroundColor Red
    Write-Log "Failed to install or upgrade Zabbix Agent v2: $_"
    exit
}

# Verify the Zabbix agent service is running
$service = Get-Service -Name "Zabbix Agent" -ErrorAction SilentlyContinue
if ($service.Status -eq 'Running') {
    Write-Log "Zabbix agent service is running."
} else {
    Write-Host "Zabbix agent service is not running. Attempting to start the service..." -ForegroundColor Yellow
    try {
        Start-Service -Name "Zabbix Agent 2" -ErrorAction Stop
        Write-Log "Zabbix agent service started successfully."
    } catch {
        Write-Host "Failed to start Zabbix agent service. Exiting script." -ForegroundColor Red
        Write-Log "Failed to start Zabbix agent service: $_"
        exit
    }
}

# Verify the TCP port 10050 is listening
$tcpPortCheck = Get-NetTCPConnection -LocalPort 10050 -State Listen -ErrorAction SilentlyContinue
if ($tcpPortCheck) {
    Write-Log "TCP port 10050 is listening."
} else {
    Write-Host "TCP port 10050 is not listening. Please check the Zabbix agent configuration." -ForegroundColor Red
    Write-Log "TCP port 10050 is not listening. Please check the Zabbix agent configuration."
    exit
}

Write-Log "Zabbix agent installation and verification completed successfully."
Write-Host "Zabbix agent installation and verification completed successfully." -ForegroundColor Green
