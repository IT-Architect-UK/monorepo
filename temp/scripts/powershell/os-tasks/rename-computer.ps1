<#
.SYNOPSIS
This script renames the computer and optionally restarts it. This version of the script allows for a custom computer name to be passed as a parameter:

> $NewComputerName

If the new computer name is not passed when calling the script, it will generate a unique name based on the Unix timestamp.

.DESCRIPTION
The script performs the following actions:
- Optionally accepts a new computer name as a command-line switch.
- Generates a unique computer name if no custom name is provided.
- Renames the computer to the specified or generated name.
- Restarts the computer.

.NOTES
Version:        1.0
Author:         IT Surgery
Modification Date:  08-03-2024

To run this script and pass the new computer name as a parameter, you would call it from the PowerShell command line like this:

```powershell
.\rename-computer.ps1 -NewComputerName "NewComputerName"
#>

param(
    # Optional parameter for custom computer name
    [string]$NewComputerName
)

function Get-UniqueNumber {
    # Get the current Unix timestamp
    $timestamp = [int][double]::Parse((Get-Date (Get-Date).ToUniversalTime() -UFormat %s))

    # Use modulo to ensure the number stays within 10 digits
    # This operation guarantees a result that's within the range of 0 to 9999999999 (10 digits)
    $uniqueNumber = $timestamp % 10000000000
    return $uniqueNumber
}

# Determine the new computer name based on whether a custom name was provided
$newName = if (-not [string]::IsNullOrEmpty($NewComputerName)) {
    $NewComputerName
} else {
    $uniqueNumber = Get-UniqueNumber
    "SVRMW$uniqueNumber"
}

# Rename the computer
Rename-Computer -NewName $newName -Force

# Restart the computer
Restart-Computer
