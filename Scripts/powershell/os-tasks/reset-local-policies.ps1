<#
.SYNOPSIS
This script removes all OS GPO & Local Policy settings to revert the system to OS defaults.

.DESCRIPTION
The script performs the following actions:
- Resets Local & Group Policy Settings To OS Default
- Deletes "$env:WinDir\System32\GroupPolicyUsers"
- Deletes "$env:WinDir\System32\GroupPolicy"

.NOTES
Version:        1.0
Author:         Darren Pilkington
Creation Date:  03-03-2024
#>

# Check if the GroupPolicyUsers directory exists
if (Test-Path "$env:WinDir\System32\GroupPolicyUsers") {
    # If it exists, remove the GroupPolicyUsers directory
    Write-Output "Removing the GroupPolicyUsers directory..."
    Remove-Item -Path "$env:WinDir\System32\GroupPolicyUsers" -Recurse -Force
    Write-Output "GroupPolicyUsers directory removed successfully."
} else {
    Write-Output "GroupPolicyUsers directory does not exist."
}

# Check if the GroupPolicy directory exists
if (Test-Path "$env:WinDir\System32\GroupPolicy") {
    # If it exists, remove the GroupPolicy directory
    Write-Output "Removing the GroupPolicy directory..."
    Remove-Item -Path "$env:WinDir\System32\GroupPolicy" -Recurse -Force
    Write-Output "GroupPolicy directory removed successfully."
} else {
    Write-Output "GroupPolicy directory does not exist."
}

# Force a Group Policy update
Write-Output "Forcing a Group Policy update..."
GPUpdate /Force
Write-Output "Group Policy update has been forced."

# Ask the user if they want to restart the computer
$userResponse = Read-Host "Do you want to restart the computer now? (Y/N)"
if ($userResponse -eq 'Y' -or $userResponse -eq 'y') {
    Write-Output "Restarting the computer..."
    Restart-Computer
} else {
    Write-Output "No restart. The script has completed its execution."
}