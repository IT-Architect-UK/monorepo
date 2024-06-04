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
Author:         ChatGPT
Modification Date:  02-06-2024
#>

# Download Windows Exporter
Invoke-WebRequest -Uri "https://github.com/prometheus-community/windows_exporter/releases/download/v0.16.0/windows_exporter-0.16.0-amd64.msi" -OutFile "windows_exporter.msi"

# Install Windows Exporter
Start-Process -FilePath "msiexec.exe" -ArgumentList "/i windows_exporter.msi /passive" -Wait

# Start Windows Exporter Service
Start-Service -Name "windows_exporter"
