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
.\Install-ZabbixAgent.ps1 -ServerIP "192.168.1.123" -ServerName "ZABBIX-SERVER.EXAMPLE.COM"

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

# Get the FQDN of the computer
$FQDN = [System.Net.Dns]::GetHostByName(($env:COMPUTERNAME)).HostName
# Convert the FQDN to uppercase
$FQDN = $FQDN.ToUpper()
# Output the capitalized FQDN
$FQDN


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
    # Chocolatey's installer, pinned: downloaded to a file, SHA256-checked
    # against the hash recorded here, then run as a file — never Invoke-
    # Expression of whatever the URL returns today. Chocolatey publishes no
    # checksum; this one was computed from install.ps1 on 2026-09-02. The
    # Chocolatey version itself is pinned via chocolateyVersion. Bump the
    # hash and version together.
    $chocoInstallSha256 = '44E045ED5350758616D664C5AF631E7F2CD10165F5BF2BD82CBF3A0BB8F63462'
    $env:chocolateyVersion = '2.7.4'
    $chocoInstaller = Join-Path $env:TEMP "choco-install-$([guid]::NewGuid()).ps1"
    Invoke-WebRequest -Uri 'https://community.chocolatey.org/install.ps1' -UseBasicParsing -OutFile $chocoInstaller
    $actual = (Get-FileHash -Path $chocoInstaller -Algorithm SHA256).Hash
    if ($actual -ne $chocoInstallSha256) {
        Remove-Item $chocoInstaller -Force -ErrorAction SilentlyContinue
        throw "Chocolatey install.ps1 checksum mismatch (got $actual) — refusing to run it. Verify the script and update chocoInstallSha256."
    }
    & $chocoInstaller
    Remove-Item $chocoInstaller -Force -ErrorAction SilentlyContinue
    Write-Log "Chocolatey installed successfully."
} else {
    Write-Log "Chocolatey is already installed."
}

# Function to install or upgrade Zabbix Agent v2
function Install-ZabbixAgent {
    # Runs choco directly with an argument list — no Invoke-Expression of a
    # command string built from variables.
    Param([string]$Action, [string]$Params)

    Write-Log "Executing: choco $Action zabbix-agent2 -y --no-progress --params '$Params'"
    & choco $Action zabbix-agent2 -y --no-progress --params $Params
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
        Install-ZabbixAgent -Action install -Params "/SERVER:$ServerName,$ServerIP /SERVERACTIVE:$ServerName,$ServerIP /HOSTNAME:$FQDN"
        Write-Log "Zabbix Agent v2 installed successfully."
    } else {
        Write-Log "Zabbix Agent v2 is already installed. Upgrading..."
        Install-ZabbixAgent -Action upgrade -Params "/SERVER:$ServerName,$ServerIP /SERVERACTIVE:$ServerName,$ServerIP /HOSTNAME:$FQDN"
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
