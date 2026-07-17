# =============================================================================
# provision-windows.ps1 — Windows Server 2025 golden image provisioning
# =============================================================================
# Run by Packer via the powershell provisioner after WinRM is available.
# Applies baseline hardening, enables RDP, installs the QEMU Guest Agent
# (Proxmox only — safely skipped on VMware), and configures OS settings.
#
# This script is idempotent — safe to run multiple times.
# =============================================================================

$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$msg) Write-Host "`n── $msg ──" -ForegroundColor Cyan }
function Write-OK   { param([string]$msg) Write-Host "  ✔  $msg" -ForegroundColor Green }
function Write-Warn { param([string]$msg) Write-Host "  ⚠  $msg" -ForegroundColor Yellow }

# ── 1. OS baseline ────────────────────────────────────────────────────────────
Write-Step "OS baseline settings"

# Timezone
Set-TimeZone -Id "UTC"
Write-OK "Timezone set to UTC"

# Set culture to en-GB
Set-Culture en-GB
Write-OK "Culture set to en-GB"

# Disable Automatic Updates (templates should not update themselves at clone time)
$auPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
New-Item -Path $auPath -Force | Out-Null
Set-ItemProperty -Path $auPath -Name "NoAutoUpdate" -Value 1 -Type DWord
Set-ItemProperty -Path $auPath -Name "AUOptions"     -Value 1 -Type DWord
Write-OK "Automatic updates disabled (re-enable after deploying from template)"

# Prevent the Microsoft Store from auto-updating inbox AppX (DesktopAppInstaller,
# etc.) during the build. Those per-user AppX updates are what break sysprep
# generalize on Windows Server 2025 (0x80073CF2). Disable this EARLY, before
# anything (internet access later in this script) can trigger an update.
$storePath = "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore"
New-Item -Path $storePath -Force | Out-Null
Set-ItemProperty -Path $storePath -Name "AutoDownload" -Value 2 -Type DWord
Write-OK "Microsoft Store app auto-update disabled (sysprep generalize protection)"

# Disable Windows Search indexing (reduces I/O on template disk)
Set-Service -Name WSearch -StartupType Disabled -ErrorAction SilentlyContinue
Stop-Service  -Name WSearch -ErrorAction SilentlyContinue
Write-OK "Windows Search indexing disabled"

# Set power plan to High Performance
powercfg /setactive SCHEME_MIN | Out-Null
Write-OK "Power plan set to High Performance"

# ── 2. Enable RDP ─────────────────────────────────────────────────────────────
Write-Step "Enable Remote Desktop"

Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
                 -Name "fDenyTSConnections" -Value 0 -Type DWord
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" `
                 -Name "UserAuthentication" -Value 0 -Type DWord    # Allow without NLA for lab use

Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
Write-OK "RDP enabled (NLA disabled for lab compatibility)"

# NOTE: WinRM is deliberately NOT hardened here. Packer is connected over
# HTTP/Basic/unencrypted for the whole build; disabling that transport
# mid-build severs Packer's own connection (401 on the next step — caught
# live). WinRM security is a DEPLOY-TIME concern (applied by Ansible when the
# server is provisioned), and sysprep resets machine config on clone anyway.

# ── 4. Firewall — baseline rules ─────────────────────────────────────────────
Write-Step "Firewall baseline"

# Re-enable the firewall (autounattend.xml disabled it; we turn it back on
# here so provisioners run inside a known-good firewall state)
Set-NetFirewallProfile -All -Enabled True | Out-Null

# Block inbound by default on all profiles
Set-NetFirewallProfile -Profile Domain,Public,Private -DefaultInboundAction Block  | Out-Null
Set-NetFirewallProfile -Profile Domain,Public,Private -DefaultOutboundAction Allow | Out-Null

# Allow RDP
New-NetFirewallRule -DisplayName "RDP-TCP-In" -Direction Inbound `
                    -Protocol TCP -LocalPort 3389 -Action Allow `
                    -ErrorAction SilentlyContinue | Out-Null

# Allow WinRM (HTTPS — 5986 recommended for production)
New-NetFirewallRule -DisplayName "WinRM-HTTPS-In" -Direction Inbound `
                    -Protocol TCP -LocalPort 5986 -Action Allow `
                    -ErrorAction SilentlyContinue | Out-Null

# Allow WinRM HTTP during Packer build (cleanup-windows.ps1 removes this rule)
New-NetFirewallRule -DisplayName "WinRM-HTTP-Packer" -Direction Inbound `
                    -Protocol TCP -LocalPort 5985 -Action Allow `
                    -ErrorAction SilentlyContinue | Out-Null

# Allow ICMP (ping) — useful in a lab
New-NetFirewallRule -DisplayName "ICMP-In" -Direction Inbound `
                    -Protocol ICMPv4 -Action Allow `
                    -ErrorAction SilentlyContinue | Out-Null

Write-OK "Firewall: block-inbound-by-default, RDP/WinRM/ICMP allowed"

# ── 5. QEMU Guest Agent (Proxmox only) ───────────────────────────────────────
Write-Step "QEMU Guest Agent (Proxmox)"

# Search all CD-ROM drives for the virtio-win guest agent installer.
# On VMware this loop finds nothing and exits cleanly.
$agentInstalled = $false
foreach ($vol in (Get-Volume | Where-Object DriveType -eq 'CD-ROM' | Where-Object DriveLetter -ne $null)) {
    $candidates = @(
        "$($vol.DriveLetter):\guest-agent\qemu-ga-x86_64.msi",
        "$($vol.DriveLetter):\virtio-win-guest-tools.exe"
    )
    foreach ($path in $candidates) {
        if (Test-Path $path) {
            Write-Host "  Found: $path"
            if ($path -like "*.msi") {
                Start-Process msiexec.exe -Wait -ArgumentList "/i `"$path`" /qn /norestart"
            } else {
                Start-Process $path -Wait -ArgumentList "/install /quiet /norestart"
            }
            $agentInstalled = $true
            Write-OK "QEMU Guest Agent installed from $path"
            break
        }
    }
    if ($agentInstalled) { break }
}

if (-not $agentInstalled) {
    Write-Warn "QEMU Guest Agent not found — skipping (expected on VMware)"
}

# ── 6. Windows Features ───────────────────────────────────────────────────────
Write-Step "Windows Features"

# Enable OpenSSH Server (useful for Ansible management later)
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction SilentlyContinue | Out-Null
Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
Start-Service -Name sshd -ErrorAction SilentlyContinue

# Allow SSH through firewall
New-NetFirewallRule -DisplayName "SSH-In" -Direction Inbound `
                    -Protocol TCP -LocalPort 22 -Action Allow `
                    -ErrorAction SilentlyContinue | Out-Null

Write-OK "OpenSSH Server installed and enabled"

# ── 7. Disable unnecessary services ──────────────────────────────────────────
Write-Step "Disable unnecessary services"

$disableServices = @(
    'TabletInputService',   # Tablet PC Input
    'PrintSpooler',         # Remove if not a print server
    'Fax',                  # Fax service
    'XblAuthManager',       # Xbox Live
    'XblGameSave',          # Xbox Game Save
    'XboxNetApiSvc',        # Xbox Networking
    'lfsvc'                 # Geolocation
)

foreach ($svc in $disableServices) {
    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($s) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Set-Service  -Name $svc -StartupType Disabled -ErrorAction SilentlyContinue
        Write-OK "Disabled: $svc"
    }
}

# ── 8. Registry hardening ─────────────────────────────────────────────────────
Write-Step "Registry hardening"

# Disable SMBv1 (legacy, insecure)
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue
Write-OK "SMBv1 disabled"

# Disable LLMNR
$llmnrPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
New-Item -Path $llmnrPath -Force | Out-Null
Set-ItemProperty -Path $llmnrPath -Name "EnableMulticast" -Value 0 -Type DWord
Write-OK "LLMNR disabled"

# Disable NetBIOS over TCP/IP (set via registry). Non-critical — never let it
# abort the build (the -Stop preference + a registry read that errors would).
try {
    $adapters = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces" -ErrorAction SilentlyContinue
    foreach ($adapter in $adapters) {
        Set-ItemProperty -Path $adapter.PSPath -Name "NetbiosOptions" -Value 2 -Type DWord -ErrorAction SilentlyContinue
    }
    Write-OK "NetBIOS over TCP/IP disabled on all adapters"
} catch {
    Write-Warn "NetBIOS tweak skipped (non-critical): $($_.Exception.Message)"
}

# Disable Windows Script Host (reduces attack surface)
# Uncomment if you don't need VBScript/JScript:
# Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings" -Name "Enabled" -Value 0 -Type DWord

# ── 9. Windows Update — download but don't auto-install ──────────────────────
Write-Step "Windows Update settings"

# Template images should be updated at build time, not when cloned.
# To update during build, uncomment the block below (adds ~30-60 min):
#
# Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck
# Import-Module PSWindowsUpdate
# Get-WindowsUpdate -AcceptAll -Install -AutoReboot
# Write-OK "Windows Updates applied"

Write-Warn "Windows Update auto-install skipped — apply updates manually after first boot or uncomment the block in this script"

# ── 10. Monorepo sync ────────────────────────────────────────────────────────
Write-Step "Monorepo sync scheduled task"
try {

# Create C:\Scripts\ and write the sync script into the image
$scriptsDir = "C:\Scripts"
if (-not (Test-Path $scriptsDir)) {
    New-Item -ItemType Directory -Path $scriptsDir -Force | Out-Null
}

# The sync script is baked in verbatim so it's available before git is installed
$syncScript = @'
$RepoUrl = "https://github.com/IT-Architect-UK/monorepo.git"
$RepoDir = "C:\Git\Monorepo"
$LogDir  = "C:\Logs\MonorepoSync"
$LogFile = Join-Path $LogDir "monorepo-sync-$(Get-Date -Format 'yyyy-MM-dd').log"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
function Write-Log { param([string]$m,[string]$l="INFO") { $e="[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$l]  $m"; Write-Host $e; Add-Content -Path $LogFile -Value $e } }
Write-Log "Monorepo sync starting on $env:COMPUTERNAME"
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) { Write-Log "git not found — skipping." "WARN"; exit 0 }
try { $null = Invoke-WebRequest -Uri "https://github.com" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop }
catch { Write-Log "GitHub not reachable — skipping." "WARN"; exit 0 }
$gitDir = Join-Path $RepoDir ".git"
if (Test-Path $gitDir) {
    $out = & git -C $RepoDir pull --ff-only 2>&1
    if ($LASTEXITCODE -eq 0) { Write-Log "Pull complete. HEAD: $(& git -C $RepoDir rev-parse --short HEAD)" }
    else { Remove-Item -Path $RepoDir -Recurse -Force -ErrorAction SilentlyContinue; & git clone --quiet $RepoUrl $RepoDir 2>&1 | Out-Null; Write-Log "Reclone complete." }
} else {
    if (-not (Test-Path $RepoDir)) { New-Item -ItemType Directory -Path $RepoDir -Force | Out-Null }
    & git clone --quiet $RepoUrl $RepoDir 2>&1 | Out-Null
    Write-Log "Clone complete. HEAD: $(& git -C $RepoDir rev-parse --short HEAD 2>&1)"
}
Write-Log "Sync finished. Scripts at: $RepoDir"
'@

$syncScriptPath = Join-Path $scriptsDir "Sync-Monorepo.ps1"
Set-Content -Path $syncScriptPath -Value $syncScript -Encoding UTF8
Write-OK "Sync-Monorepo.ps1 written to $syncScriptPath"

# Register scheduled task — runs as SYSTEM, no password required
$taskName   = "MonorepoSync"
$psExe      = "powershell.exe"
$psArgs     = "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$syncScriptPath`""

$action     = New-ScheduledTaskAction -Execute $psExe -Argument $psArgs
$trigBoot   = New-ScheduledTaskTrigger -AtStartup
$trigBoot.Delay = "PT1M"          # 1-minute delay for network stack to be ready
$trigDaily  = New-ScheduledTaskTrigger -Daily -At "01:00"
$principal  = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings   = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 15) `
                                            -StartWhenAvailable `
                                            -MultipleInstances IgnoreNew

# Remove existing task if present (idempotent)
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask `
    -TaskName   $taskName `
    -Action     $action `
    -Trigger    @($trigBoot, $trigDaily) `
    -Principal  $principal `
    -Settings   $settings `
    -Description "Clones/pulls the IT-Architect monorepo to C:\Git\Monorepo. Scripts available at C:\Git\Monorepo\infrastructure\" | Out-Null

Write-OK "Scheduled task '$taskName' registered (AtStartup +1min, daily 01:00, SYSTEM)"

# Initial clone best-effort — git may not be in PATH yet if Chocolatey step is pending
Write-Host "  Running initial monorepo clone (best-effort) ..." -ForegroundColor Gray
try {
    & powershell.exe -NonInteractive -ExecutionPolicy Bypass -File $syncScriptPath
    Write-OK "Initial clone complete. Repo available at C:\Git\Monorepo"
} catch {
    Write-Warn "Initial clone skipped — will run on first boot (git may not be installed yet)"
}

} catch {
    Write-Warn "Monorepo sync task setup skipped (non-critical): $($_.Exception.Message)"
}

# ── Done ──────────────────────────────────────────────────────────────────────
# ── 11. Post-clone script (triggered by the deploy via the QEMU guest agent) ──
# cloudbase-init handles hostname + network on Proxmox, but it CANNOT apply the
# user/password (Proxmox writes those as cloud-config user-data, unsupported by
# cloudbase). So the deploy runs this script via the guest agent to: set the
# admin account + password, remove the trailing recovery partition and extend
# C: into the resized disk, then reboot (which applies the pending hostname).
Write-Step "Stage post-clone script (account + disk + hostname)"
try {
    if (-not (Test-Path "C:\Scripts")) { New-Item -ItemType Directory -Path "C:\Scripts" -Force | Out-Null }
    $postClone = @'
param(
    [string]$AdminUser = 'it-admin',
    [string]$AdminPassword = '',
    [string]$Hostname = ''
)
$ErrorActionPreference = 'Continue'
$logDir = 'C:\Logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$log = Join-Path $logDir 'post-clone.log'
function L($m) { $line = "$(Get-Date -Format 's') $m"; Add-Content -Path $log -Value $line; Write-Output $line }

L "post-clone starting (user=$AdminUser host=$Hostname current=$env:COMPUTERNAME)"
Start-Sleep -Seconds 15
L "settle wait complete"

# 1. admin account
if ($AdminPassword) {
    try {
        $sec = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
        if (Get-LocalUser -Name $AdminUser -ErrorAction SilentlyContinue) {
            Set-LocalUser -Name $AdminUser -Password $sec; L "reset password for $AdminUser"
        } else {
            New-LocalUser -Name $AdminUser -Password $sec -FullName $AdminUser -AccountNeverExpires -PasswordNeverExpires -ErrorAction SilentlyContinue | Out-Null
            L "created $AdminUser"
        }
        Add-LocalGroupMember -Group 'Administrators' -Member $AdminUser -ErrorAction SilentlyContinue
        L "$AdminUser added to local Administrators"
    } catch { L "account error: $($_.Exception.Message)" }
} else { L "account: no password supplied, skipped" }

# 1b. remove Packer build account
try {
    if (Get-LocalUser -Name 'packer' -ErrorAction SilentlyContinue) { Remove-LocalUser -Name 'packer' -ErrorAction SilentlyContinue; L "removed build account packer" }
} catch { L "packer error: $($_.Exception.Message)" }
Remove-Item -Path 'C:\Users\packer' -Recurse -Force -ErrorAction SilentlyContinue

# 2. remove trailing recovery partition + extend C: (inline diskpart)
try {
    $cPart = Get-Partition -DriveLetter C
    reagentc /disable 2>&1 | Out-Null
    $cmds = @("select disk $($cPart.DiskNumber)")
    Get-Partition -DiskNumber $cPart.DiskNumber | Where-Object { $_.PartitionNumber -gt $cPart.PartitionNumber } | ForEach-Object { $cmds += "select partition $($_.PartitionNumber)"; $cmds += "delete partition override" }
    $cmds += "select volume c"; $cmds += "extend"; $cmds += "exit"
    $f = Join-Path $env:TEMP "dp_extend.txt"; Set-Content -Path $f -Value $cmds -Encoding Ascii
    diskpart /s $f | Out-Null
    L "removed recovery partition + extended C: (diskpart)"
} catch { L "extend error: $($_.Exception.Message)" }

# 3. CD/DVD -> Z: (inline diskpart; cloud-init CD is at D: on a fresh clone)
try {
    $f = Join-Path $env:TEMP "dp_cd.txt"; Set-Content -Path $f -Value @("select volume D", "assign letter=Z", "exit") -Encoding Ascii
    diskpart /s $f | Out-Null
    L "moved CD/DVD D: -> Z: (diskpart)"
} catch { L "cd error: $($_.Exception.Message)" }

# 4. data disk -> D: 'Apps & Data' (inline diskpart)
try {
    $raw = Get-Disk | Where-Object { $_.PartitionStyle -eq 'RAW' } | Sort-Object Number | Select-Object -First 1
    if ($raw) {
        $dcmds = @("select disk $($raw.Number)", "clean", "convert gpt", "create partition primary", "format fs=ntfs quick label=`"Apps & Data`"", "assign letter=D", "exit")
        $f = Join-Path $env:TEMP "dp_data.txt"; Set-Content -Path $f -Value $dcmds -Encoding Ascii
        diskpart /s $f | Out-Null
        L "data disk initialised as D: (Apps & Data)"
    } else { L "no raw data disk present" }
} catch { L "data disk error: $($_.Exception.Message)" }

# 5. label C: as OS
try { cmd /c "label C: OS" 2>&1 | Out-Null; L "labelled C: as OS" } catch { L "label error: $($_.Exception.Message)" }

# 6. hostname via registry (Rename-Computer hangs headless); deploy reboots
if ($Hostname -and $env:COMPUTERNAME -ne $Hostname) {
    try {
        $cn = "HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName"
        Set-ItemProperty -Path "$cn\ComputerName" -Name "ComputerName" -Value $Hostname
        Set-ItemProperty -Path "$cn\ActiveComputerName" -Name "ComputerName" -Value $Hostname
        $tcp = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
        Set-ItemProperty -Path $tcp -Name "Hostname" -Value $Hostname
        Set-ItemProperty -Path $tcp -Name "NV Hostname" -Value $Hostname
        L "set hostname to $Hostname (registry)"
    } catch { L "hostname error: $($_.Exception.Message)" }
} else { L "hostname: no change needed (current=$env:COMPUTERNAME)" }

L "post-clone COMPLETE"

'@
    Set-Content -Path "C:\Scripts\Invoke-WindowsPostClone.ps1" -Value $postClone -Encoding UTF8
    Write-OK "Invoke-WindowsPostClone.ps1 staged (deploy runs it after clone)"
} catch {
    Write-Warn "Could not stage post-clone script (non-critical): $($_.Exception.Message)"
}

Write-Host "`n✔  provision-windows.ps1 complete" -ForegroundColor Green
