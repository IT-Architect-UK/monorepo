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
Author:         Darren Pilkington
Modification Date:  06-06-2024
#>

# Define installation and log directories
$windowsExporterExtractPath = "C:\Program Files\Prometheus Node Exporter"
$logDirectory = "C:\Logs"

# Create log directory if it doesn't exist
if (-not (Test-Path $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory -Force
}

# Define log file with timestamp
$logFile = "$logDirectory\windows_exporter_install_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Function to log messages
function Log-Message {
    param (
        [string]$message
    )
    Write-Host $message
    Add-Content -Path $logFile -Value $message
}

# Function to get the latest Windows Exporter version
function Get-LatestWindowsExporterVersion {
    $url = "https://api.github.com/repos/prometheus-community/windows_exporter/releases/latest"
    $response = Invoke-RestMethod -Uri $url
    return $response.tag_name.TrimStart('v')
}

# Get the latest Windows Exporter version
$latestVersion = Get-LatestWindowsExporterVersion
Log-Message "Latest Windows Exporter version: $latestVersion"

# Remove existing Node Exporter and scheduled task if they exist
if (Test-Path "$windowsExporterExtractPath\windows_exporter.exe") {
    Log-Message "Stopping existing Windows Exporter task if running..."
    $task = Get-ScheduledTask -TaskName "Prometheus Node Exporter" -ErrorAction SilentlyContinue
    if ($task) {
        Stop-ScheduledTask -TaskName "Prometheus Node Exporter" -ErrorAction SilentlyContinue
        Sleep 5
    }
    Log-Message "Removing existing Windows Exporter installation..."
    Remove-Item -Recurse -Force -Path "$windowsExporterExtractPath"
}

if (Get-ScheduledTask -TaskName "Prometheus Node Exporter" -ErrorAction SilentlyContinue) {
    Log-Message "Removing existing scheduled task..."
    Unregister-ScheduledTask -TaskName "Prometheus Node Exporter" -Confirm:$false
}

# Download and install/upgrade Windows Exporter
Log-Message "Installing Windows Exporter version $latestVersion"

# Construct the download URL
$windowsExporterDownloadUrl = "https://github.com/prometheus-community/windows_exporter/releases/download/v$latestVersion/windows_exporter-$latestVersion-amd64.exe"

# Echo the download URL for debugging
Log-Message "Download URL: $windowsExporterDownloadUrl"

$exeFilePath = "$env:TEMP\windows_exporter-$latestVersion-amd64.exe"
try {
    Invoke-WebRequest -Uri $windowsExporterDownloadUrl -OutFile $exeFilePath -ErrorAction Stop
    if (-not (Test-Path $exeFilePath)) {
        throw "Download failed: File not found after download attempt."
    }
    Log-Message "Downloaded Windows Exporter to $exeFilePath"
} catch {
    Log-Message "Failed to download Windows Exporter. Error: $_"
    exit 1
}

# Create installation directory if it doesn't exist
if (-not (Test-Path $windowsExporterExtractPath)) {
    New-Item -ItemType Directory -Path $windowsExporterExtractPath -Force
    Log-Message "Created directory $windowsExporterExtractPath"
}

# Move Windows Exporter executable to installation directory
Move-Item -Path $exeFilePath -Destination "$windowsExporterExtractPath\windows_exporter.exe" -Force
Log-Message "Moved Windows Exporter to $windowsExporterExtractPath"

# Define Windows Exporter arguments
$exporterArgs = @("--collectors.enabled=ad,adfs,cache,cpu,cpu_info,cs,container,dfsr,dhcp,dns,fsrmquota,iis,logical_disk,logon,memory,msmq,mssql,netframework_clrexceptions,netframework_clrinterop,netframework_clrjit,netframework_clrloading,netframework_clrlocksandthreads,netframework_clrmemory,netframework_clrremoting,netframework_clrsecurity,net,os,process,remote_fx,service,tcp,time,vmware")

# Combine arguments
$exporterArgsString = $exporterArgs -join ","
Log-Message "Windows Exporter arguments: $exporterArgsString"

# Create Scheduled Task to run Windows Exporter
$trigger = New-ScheduledTaskTrigger -AtStartup
$action = New-ScheduledTaskAction -Execute "$windowsExporterExtractPath\windows_exporter.exe" -Argument $exporterArgsString
$settings = New-ScheduledTaskSettingsSet -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount

# Register the scheduled task
Register-ScheduledTask -TaskName "Prometheus Node Exporter" -Action $action -Trigger $trigger -Settings $settings -Principal $principal
Log-Message "Scheduled task 'Prometheus Node Exporter' created."

# Start the scheduled task
Start-ScheduledTask -TaskName "Prometheus Node Exporter"
if ($?) {
    Log-Message "Scheduled task 'Prometheus Node Exporter' started successfully."
} else {
    Log-Message "Failed to start scheduled task 'Prometheus Node Exporter'."
}

Write-Host "Windows Exporter version $latestVersion installed and configured."
