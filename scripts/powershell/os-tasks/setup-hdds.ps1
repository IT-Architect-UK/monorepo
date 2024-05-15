<#
.SYNOPSIS
This script configures virtual hard disks on a Windows system.

.DESCRIPTION
The script performs the following actions:
- Renames the C: drive label to "OS".
- Changes the CD-ROM drive letter to Z: if present.
- Initializes and formats RAW disks with GPT partition style.
- Assigns drive letters dynamically to new data disks, starting from D:.
- Renames the D: drive label to "Applications & Data".
- Renames the remaining drive labels match their assigned drive letter.

.NOTES
Version:        1.0
Author:         Darren Pilkington
Creation Date:  03-03-2024
#>

# Function to find the next available drive letter
function Get-NextAvailableDriveLetter {
    $usedLetters = (Get-Partition | Where-Object DriveLetter -ne $null).DriveLetter
    $alphabet = 67..90 | ForEach-Object { [char]$_ }  # C to Z
    $availableLetters = $alphabet | Where-Object { $_ -notin $usedLetters }
    return $availableLetters[0]
}

Write-Output "Configuring the virtual hard disks"

Write-Output "Renaming the C: drive label to OS"
Get-Volume -DriveLetter C | Set-Volume -NewFileSystemLabel "OS"

Write-Output "Get the CD-ROM drive information"
$cdRomDrive = Get-CimInstance -ClassName Win32_CDROMDrive

Write-Output "If a CD-ROM drive is found, change its drive letter to Z:"
if ($cdRomDrive) {
    Get-WmiObject -Class win32_volume -Filter "DriveLetter = '$($cdRomDrive.Drive)' " | Set-WmiInstance -Arguments @{DriveLetter='Z:'}
}

Write-Output "Get all the disks on the system"
$disks = Get-Disk

Write-Output "Filter out the disks that have a RAW partition style (i.e., unformatted)"
$rawDisks = $disks | Where-Object PartitionStyle -eq 'RAW'

Write-Output "Initialize a counter for data disks"
$dataDiskCount = 1

Write-Output "Loop through each RAW disk to initialize and format it"
foreach ($disk in $rawDisks) {
    $diskNumber = $disk.Number

    Write-Output "Initialize the disk with GPT partition style"
    Initialize-Disk -Number $diskNumber -PartitionStyle GPT -PassThru

    Write-Output "Create a new partition using the maximum available size on the disk"
    $partition = New-Partition -DiskNumber $diskNumber -UseMaximumSize

    if ($dataDiskCount -eq 1) {
        Write-Output "If this is the first data disk, assign it the letter D: and label it Applications & Data"
        $partition | Set-Partition -NewDriveLetter 'D'
        Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel "Applications & Data" -Confirm:$false
    } else {
        Write-Output "For subsequent data disks, assign the next available drive letter and label it 'Data'"
        $nextLetter = Get-NextAvailableDriveLetter
        $partition | Set-Partition -NewDriveLetter $nextLetter
        Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel $nextLetter -Confirm:$false
    }
    $dataDiskCount++
}

Write-Output "Hard Disk Configuration Complete"
Write-Output "Please update assigned drive letter and labels as required"