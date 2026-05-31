<#
.SYNOPSIS
This script ensures a fresh copy of a specified Git repository is downloaded to the local system.

.DESCRIPTION
The script performs the following actions:
- Checks for Git installation and stops with an error if Git is not installed.
- Installs necessary PowerShell modules (PackageManagement, PendingReboot).
- Determines the best available drive (prefers D:\ over C:\) to store the repository.
- Deletes the repository if it already exists, then clones a fresh copy to the specified location.

.PARAMETER repoUrl
The URL of the Git repository to clone. Default value is 'https://github.com/IT-Surgery/scripts.git'.

.EXAMPLE
PS> .\UpdateGitRepo.ps1
Executes the script using the default repository URL.

.EXAMPLE
PS> .\UpdateGitRepo.ps1 -repoUrl 'https://github.com/SomeOtherUser/OtherRepo.git'
Executes the script using a custom repository URL.

.NOTES
Version:        1.0
Author:         IT Surgery
Creation Date:  03-15-2024
#>

# Logging function
function Write-Log {
    Param ([string]$Message)
    Write-Output $Message
    $Message | Out-File -FilePath $logFilePath -Append -Encoding UTF8
}

# Define the repository URL
$repoUrl = 'https://github.com/IT-Surgery/scripts.git'


# Installing Git using Chocolatey if it is not already installed
Write-Output "Installing Git using Chocolatey if it is not already installed ..."

# Configuring Log Settings
Write-Output "Configuring Log Settings ..."
$logDrive = if (Test-Path D:\) { "D:\" } else { "C:\" }
$logPath = Join-Path -Path $logDrive -ChildPath "Logs\Chocolatey\"
$dateTime = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = "Install-Chocolatey-$dateTime.log"
$logFilePath = Join-Path -Path $logPath -ChildPath $logFile
if (-not (Test-Path $logPath)) {New-Item -ItemType Directory -Path $logPath -Force | Out-Null}

$chocoPackages = 'git'
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
Write-Log "Chocolatey is installed. Continuing with script ..."

Write-Output "Installing Git if it is not already installed ..."

Write-Output "Configuring Log Settings."
$logDrive = if (Test-Path D:\) { "D:\" } else { "C:\" }
$logPath = Join-Path -Path $logDrive -ChildPath "Logs\Git\"
$dateTime = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = "Install-Git-$dateTime.log"
$logFilePath = Join-Path -Path $logPath -ChildPath $logFile
if (-not (Test-Path $logPath)) {New-Item -ItemType Directory -Path $logPath -Force | Out-Null}
Write-Log "Installing the Git Chocolatey Package ..."
foreach ($package in $chocoPackages) {
    try {
        if (!(choco list --local-only | Select-String -Pattern $package)) {
            choco install $package -y --no-progress | Out-Null
            Write-Log "$package installed successfully."
        }
    } catch {Write-Log "$package is already installed or encountered an error."}
}
Write-Log "Reloading environmental PATH variables ..."
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
Write-Log "Checking for Git installation"
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {throw "Git must be installed to use this script."}
Write-Log "Git is installed. Version: $(git --version)"

# Installing PowerShell Modules
Write-Output "Installing PowerShell Modules ..."
Write-Output "Configuring Log Settings."
$logDrive = if (Test-Path D:\) { "D:\" } else { "C:\" }
$logPath = Join-Path -Path $logDrive -ChildPath "Logs\PowerShell\"
$dateTime = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = "Install-PowerShell-Modules-$dateTime.log"
$logFilePath = Join-Path -Path $logPath -ChildPath $logFile
if (-not (Test-Path $logPath)) {New-Item -ItemType Directory -Path $logPath -Force | Out-Null}

Write-Log "Installing PowerShell Modules"
Install-PackageProvider -Name NuGet -Force
$modules = 'PackageManagement', 'PendingReboot'
foreach ($module in $modules) {
    if (Get-Module -ListAvailable -Name $module) {Write-Log "Module $module is already installed."}
    else {
        Write-Log "Installing module $module."
        Install-Module -Name $module -SkipPublisherCheck -Force
    }
    Import-Module $module
}

# Cloning Git Repository
Write-Output "Cloning Git Repository ..."
Write-Output "Configuring Log Settings."
$logDrive = if (Test-Path D:\) { "D:\" } else { "C:\" }
$logPath = Join-Path -Path $logDrive -ChildPath "Logs\Git\"
$dateTime = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = "Clone-Git-Repo-$dateTime.log"
$logFilePath = Join-Path -Path $logPath -ChildPath $logFile
if (-not (Test-Path $logPath)) {New-Item -ItemType Directory -Path $logPath -Force | Out-Null}

# Determine the save location based on the availability of the D:\ drive
Write-Log "Setting the target directory for the Git clone."
$drive = if (Test-Path D:\) { "D:\" } else { "C:\" }
$urlParts = $repoUrl -split '/'
$repoOwner = $urlParts[-2] # The second to last element is typically the owner or organization name
$repoName = $urlParts[-1] -replace '\.git$', '' # The last element is the repository name
$saveLocation = Join-Path -Path $drive -ChildPath "Git\$repoOwner\$repoName"

# Clone or refresh the repository
if (Test-Path $saveLocation) {Write-Log "Repository exists at $saveLocation. Deleting for a fresh clone."
    Remove-Item -Path $saveLocation -Recurse -Force
}

Write-Log "Cloning the repository to $saveLocation"
$gitCommand = "git clone '$repoUrl' '$saveLocation' 2>&1"
Start-Process -FilePath "powershell.exe" -ArgumentList "-Command", $gitCommand -Wait -WindowStyle Hidden | Out-File -FilePath $logFilePath -Append -Encoding utf8
