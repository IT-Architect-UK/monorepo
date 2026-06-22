#Requires -Version 5.1
<#
.SYNOPSIS
    Runs Sysprep to generalise a Windows VM ready for templating.

.DESCRIPTION
    Sysprep (System Preparation Tool) removes machine-specific information from
    a Windows installation so it can be cloned or distributed safely.

    What Sysprep removes:
    ─────────────────────
    - SID (Security Identifier) — unique ID used by Active Directory
    - Computer name
    - Hardware profile
    - Plug-and-play device state
    - Local user account passwords (optionally)

    After Sysprep, the VM shuts down. You then:
    - Convert it to a template (VMware) or take a snapshot (Hyper-V / Proxmox)
    - Each clone gets a new SID and hostname on first boot (OOBE)

    WARNING: Sysprep is destructive. Run it only on a VM dedicated to templating.
    Do NOT run it on a production server.

.PARAMETER ShutdownMode
    What to do after Sysprep:
    - Shutdown  (default) — shut down the VM for templating
    - Reboot    — OOBE runs on this machine (for testing)
    - Quit      — Sysprep runs but doesn't shut down (for inspection)

.PARAMETER SkipWindowsUpdate
    Skip applying Windows Updates before sealing. Not recommended.

.PARAMETER UnattendFile
    Path to a custom unattend.xml file for OOBE automation. If not specified,
    a default is used that prompts for username/password/locale on first boot.

.EXAMPLE
    # Full seal with updates — recommended for template creation
    .\sysprep-and-seal.ps1

.EXAMPLE
    # Seal without updates (faster, use if updates were already applied)
    .\sysprep-and-seal.ps1 -SkipWindowsUpdate

.NOTES
    Run this script locally on the Windows VM you want to template.
    You will need to re-activate Windows on each clone (or use KMS/AVMA).

    Author  : IT-Architect-UK
    Repo    : https://github.com/IT-Architect-UK/monorepo
    Version : 1.0.0
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [ValidateSet('Shutdown', 'Reboot', 'Quit')]
    [string]$ShutdownMode = 'Shutdown',

    [Parameter()]
    [switch]$SkipWindowsUpdate,

    [Parameter()]
    [string]$UnattendFile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step   { param($m) Write-Host "[>] $m" -ForegroundColor Cyan }
function Write-OK     { param($m) Write-Host "[✔] $m" -ForegroundColor Green }
function Write-Warn   { param($m) Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-Fail   { param($m) Write-Host "[✘] $m" -ForegroundColor Red; throw $m }
function Write-Header { param($m) Write-Host "`n━━━ $m ━━━`n" -ForegroundColor Blue }

Write-Header "Windows Sysprep & Seal"
Write-Warn "This will PERMANENTLY modify this VM. Run only on a template VM."
$confirm = Read-Host "Type 'YES' to continue"
if ($confirm -ne 'YES') { Write-Host "Aborted."; exit 0 }

# ── Check we're running as Administrator ──────────────────────────────────
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Fail "Run this script as Administrator"
}

# ── Apply Windows Updates ─────────────────────────────────────────────────
if (-not $SkipWindowsUpdate) {
    Write-Header "Applying Windows Updates"
    Write-Step "Installing PSWindowsUpdate module..."

    if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Install-Module -Name PSWindowsUpdate -Force -Confirm:$false
    }

    Write-Step "Applying all available updates (this may take 10-30 minutes)..."
    Import-Module PSWindowsUpdate
    $updates = Get-WindowsUpdate -AcceptAll -Install -AutoReboot:$false

    if ($updates.Count -gt 0) {
        Write-OK "$($updates.Count) update(s) applied"
        $pendingReboot = (Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired")
        if ($pendingReboot) {
            Write-Warn "A reboot is required to complete updates."
            Write-Warn "Please reboot, log back in as Administrator, and re-run this script."
            exit 0
        }
    } else {
        Write-OK "System is fully up to date"
    }
}

# ── Pre-Sysprep Cleanup ───────────────────────────────────────────────────
Write-Header "Pre-Sysprep Cleanup"

Write-Step "Clearing Windows Event Logs..."
wevtutil el | ForEach-Object { wevtutil cl $_ 2>$null }
Write-OK "Event logs cleared"

Write-Step "Clearing Temp files..."
Remove-Item -Recurse -Force "$env:TEMP\*" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "C:\Windows\Temp\*" -ErrorAction SilentlyContinue
Write-OK "Temp files cleared"

Write-Step "Clearing Windows Update cache..."
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "C:\Windows\SoftwareDistribution\Download\*" -ErrorAction SilentlyContinue
Start-Service -Name wuauserv -ErrorAction SilentlyContinue
Write-OK "Windows Update cache cleared"

# ── Create unattend.xml if not provided ──────────────────────────────────
if (-not $UnattendFile) {
    Write-Step "Creating default unattend.xml..."
    $UnattendFile = "C:\Windows\System32\Sysprep\unattend.xml"
    # Minimal unattend — prompts for user setup on first boot
    @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64"
                   publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <InputLocale>en-GB</InputLocale>
            <SystemLocale>en-GB</SystemLocale>
            <UILanguage>en-GB</UILanguage>
            <UserLocale>en-GB</UserLocale>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64"
                   publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <NetworkLocation>Work</NetworkLocation>
                <ProtectYourPC>1</ProtectYourPC>
            </OOBE>
        </component>
    </settings>
</unattend>
'@ | Set-Content -Path $UnattendFile -Encoding UTF8
    Write-OK "unattend.xml created"
}

# ── Run Sysprep ───────────────────────────────────────────────────────────
Write-Header "Running Sysprep"
$sysprepArgs = "/oobe /generalize /$($ShutdownMode.ToLower()) /quiet /unattend:`"$UnattendFile`""

Write-Warn "Sysprep is starting. The VM will $ShutdownMode after completion."
Write-Warn "Do NOT interrupt this process."

$proc = Start-Process -FilePath "C:\Windows\System32\Sysprep\sysprep.exe" `
    -ArgumentList $sysprepArgs `
    -PassThru -Wait

if ($proc.ExitCode -ne 0) {
    Write-Fail "Sysprep failed with exit code $($proc.ExitCode). Check: C:\Windows\System32\Sysprep\Panther\setuperr.log"
}

Write-OK "Sysprep completed successfully"
if ($ShutdownMode -eq 'Shutdown') {
    Write-OK "VM will shut down — convert it to a template in vCenter/Proxmox"
}
