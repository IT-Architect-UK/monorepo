<#
.SYNOPSIS
    Initialises and formats all unformatted (RAW) hard disks on the server.

.DESCRIPTION
    Performs the following operations:
      1. Renames the C: drive label to "OS"
      2. Moves the CD-ROM drive to drive letter Z: (if present)
      3. For each RAW (unformatted) disk:
           - Initialises with GPT partition style
           - Creates a single partition using the full disk size
           - Formats with NTFS
           - Assigns drive letter D: to the first data disk (labelled "Data")
           - Assigns subsequent letters alphabetically
    Safe to run on a server with no unformatted disks — no changes will be made.

.EXAMPLE
    .\setup-hdds.ps1

.NOTES
    Version:           1.1
    Author:            Darren Pilkington
    Modification Date: 31-05-2026
    Requires:          Local Administrator rights
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ─── Logging ─────────────────────────────────────────────────────────────────
$LogDirectory = if (Test-Path 'D:\') { 'D:\Logs\DiskSetup' } else { 'C:\Logs\DiskSetup' }
if (-not (Test-Path $LogDirectory)) {
    New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
}
$LogFile = Join-Path $LogDirectory "setup-hdds-$(Get-Date -Format 'yyyy-MM-dd-HH-mm-ss').log"

function Write-Log {
    param(
        [string] $Message,
        [ValidateSet('INFO','WARN','ERROR')] [string] $Level = 'INFO'
    )
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level]  $Message"
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

function Get-NextAvailableDriveLetter {
    # Returns the next unused drive letter from D onwards
    $usedLetters = (Get-Partition | Where-Object { $null -ne $_.DriveLetter }).DriveLetter
    $candidates  = 68..90 | ForEach-Object { [char]$_ }  # D to Z
    return ($candidates | Where-Object { $_ -notin $usedLetters })[0]
}

Write-Log "Disk setup starting on $env:COMPUTERNAME."
Write-Log "Log file: $LogFile"

# ─── Pre-flight ──────────────────────────────────────────────────────────────
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "Script must be run as Administrator." -Level ERROR
    exit 1
}

# ─── Rename OS drive label ────────────────────────────────────────────────────
Write-Log "Renaming C: drive label to 'OS'..."
try {
    Get-Volume -DriveLetter C | Set-Volume -NewFileSystemLabel 'OS'
    Write-Log "C: drive label set to 'OS'."
} catch {
    Write-Log "Could not rename C: drive label: $_" -Level WARN
}

# ─── Move CD-ROM to Z: ────────────────────────────────────────────────────────
Write-Log "Checking for CD-ROM drive..."
$cdRom = Get-CimInstance -ClassName Win32_CDROMDrive -ErrorAction SilentlyContinue
if ($cdRom) {
    Write-Log "CD-ROM found at $($cdRom.Drive). Moving to Z:..."
    # CIM-based volume query — avoids deprecated Get-WmiObject
    $cdVolume = Get-CimInstance -ClassName Win32_Volume `
        -Filter "DriveLetter = '$($cdRom.Drive)'" -ErrorAction SilentlyContinue
    if ($cdVolume) {
        Set-CimInstance -InputObject $cdVolume -Property @{ DriveLetter = 'Z:' }
        Write-Log "CD-ROM moved to Z:."
    }
} else {
    Write-Log "No CD-ROM drive found."
}

# ─── Initialise and format RAW disks ─────────────────────────────────────────
Write-Log "Scanning for unformatted (RAW) disks..."
$rawDisks = Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' }

if ($rawDisks.Count -eq 0) {
    Write-Log "No RAW disks found — nothing to initialise."
} else {
    Write-Log "$($rawDisks.Count) RAW disk(s) found."
    $dataDiskCount = 1

    foreach ($disk in $rawDisks) {
        Write-Log "Processing Disk $($disk.Number) ($([math]::Round($disk.Size / 1GB, 1)) GB)..."

        # Initialise with GPT
        Initialize-Disk -Number $disk.Number -PartitionStyle GPT -PassThru | Out-Null
        Write-Log "  Disk $($disk.Number): initialised with GPT."

        # Create partition using full disk
        $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize
        Write-Log "  Disk $($disk.Number): partition created."

        if ($dataDiskCount -eq 1) {
            # First data disk gets D: and label "Data"
            $partition | Set-Partition -NewDriveLetter 'D'
            Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel 'Data' -Confirm:$false | Out-Null
            Write-Log "  Disk $($disk.Number): formatted NTFS, drive letter D:, label 'Data'."
        } else {
            $nextLetter = Get-NextAvailableDriveLetter
            $partition | Set-Partition -NewDriveLetter $nextLetter
            $label = "Data-$nextLetter"
            Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel $label -Confirm:$false | Out-Null
            Write-Log "  Disk $($disk.Number): formatted NTFS, drive letter ${nextLetter}:, label '$label'."
        }

        $dataDiskCount++
    }
}

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Log "Disk configuration complete."
Write-Log "Current volumes:"
Get-Volume | Where-Object { $null -ne $_.DriveLetter } |
    ForEach-Object { Write-Log "  $($_.DriveLetter): [$($_.FileSystemLabel)] $($_.FileSystem) $([math]::Round($_.Size/1GB,1))GB" }
Write-Log "Log file: $LogFile"
Write-Log "Review drive letters and labels and update as required."
