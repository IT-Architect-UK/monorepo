<#
.SYNOPSIS
This script removes WSUS settings from the registry, checks for Windows updates, installs the NuGet provider without user input, and applies updates. It logs all actions to D:\Logs\WindowsUpdate if available, otherwise to the system drive. It also displays update installation progress.

.DESCRIPTION
The script performs the following actions:
- Removes WSUS registry settings if they exist.
- Ensures the NuGet and PSWindowsUpdate providers are installed without user input.
- Restarts the Windows Update service to apply changes.
- Checks for the presence of a specific log file in the Logs directory on D:\ or the system drive; if not found, proceeds with the update process.
- Logs the list of available updates and the results of the updates installation.
- Displays update installation progress in the PowerShell window.

.NOTES
Version:        1.0
Author:         IT Surgery
Modification Date:  08-03-2024
#>

Write-Output "Remove WSUS settings from the registry"
$wsusRegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
if (Test-Path $wsusRegPath) {
    Remove-ItemProperty -Path $wsusRegPath -Name WUServer -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $wsusRegPath -Name WUStatusServer -ErrorAction SilentlyContinue
}

Write-Output "Restarting the Windows Update service to apply changes"
Restart-Service -Name wuauserv -Force

Write-Output "Installing the NuGet provider if it's not already installed"
if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
    Install-PackageProvider -Name NuGet -Force -Scope CurrentUser
}

Write-Output "Installing the PSWindowsUpdate module if it's not already installed"
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Install-Module -Name PSWindowsUpdate -Force -Confirm:$false
}

Write-Output "Importing the PSWindowsUpdate module"
Import-Module PSWindowsUpdate
# Allow the module to access the Windows Update API
Add-WUServiceManager -ServiceID 7971f918-a847-4430-9279-4a52d1efe18d -Confirm:$false

# Check if D:\ is available and is not a CD/DVD drive
# Get all available drives
$allDrives = Get-PSDrive -PSProvider FileSystem
$driveD = $allDrives | Where-Object { $_.Root -eq 'D:\' }
if ($driveD) {
    Write-Output "D:\ is available as a local disk. Logs will be written to D:\Logs\WindowsUpdate"
    $logsDir = "D:\Logs\WindowsUpdate"
} else {
    Write-Output "D:\ is not available. Using system drive for logs."
    $logsDir = "$env:SystemDrive\Logs\WindowsUpdate"
}

$logFile = "$logsDir\windows-update-install-log-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".log"

Write-Output "Creating the Logs directory if it doesn't exist"
if (-not (Test-Path $logsDir)) {
    New-Item -Path $logsDir -ItemType Directory | Out-Null
    Write-Output "Created logs directory at $logsDir"
}

# Check for the presence of the log file
if (Test-Path $logFile) {
    Write-Output "Log file exists. Windows Update has already completed. Skipping ..."
} else {
    # Get the list of available updates
    $updates = Get-WindowsUpdate -MicrosoftUpdate
    # Log the list of available updates
    if ($updates.Count -gt 0) {
        Write-Output "Updates available:" | Out-File $logFile -Append
        $updates | ForEach-Object {
            $updateInfo = "$($_.Title)"
            Write-Output $updateInfo
            Write-Output $updateInfo | Out-File $logFile -Append
        }
    } else {
        Write-Output "No updates available." | Out-File $logFile -Append
    }
    Write-Output "Installing the latest Windows Updates and recording the results in the log file"
    $installResults = Get-WindowsUpdate -AcceptAll -AutoReboot -ForceInstall -Install -MicrosoftUpdate -Confirm:$false
    if ($installResults) {
        Write-Output "Updates installed:" | Out-File $logFile -Append
        $installResults | ForEach-Object {
            $installResultInfo = "$($_.Title) installed successfully."
            Write-Output $installResultInfo
            Write-Output $installResultInfo | Out-File $logFile -Append
        }
    } else {
        Write-Output "No updates were installed." | Out-File $logFile -Append
    }
}
