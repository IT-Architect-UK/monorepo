# =============================================================================
# install-cloudbase-init.ps1 — Windows cloud-init (Cloudbase-Init) for Proxmox
# =============================================================================
# Run by Packer AFTER provision-windows.ps1 and BEFORE cleanup-windows.ps1.
# Installs Cloudbase-Init and configures it to read Proxmox's ConfigDrive2
# drive on first boot after clone, applying hostname, network (static/DHCP),
# the admin user + password, and SSH public keys — the Windows equivalent of
# cloud-init on the Ubuntu goldens.
#
# Sealing: this script drops Cloudbase-Init's Unattend.xml at the path the
# existing cleanup-windows.ps1 already feeds to sysprep (/unattend:), so the
# specialize pass runs Cloudbase-Init on the next boot. No change needed to
# the sysprep step itself.
#
# Idempotent — safe to re-run.
# =============================================================================

$ErrorActionPreference = 'Stop'

function Write-Step { param([string]$msg) Write-Host "`n== $msg ==" -ForegroundColor Cyan }
function Write-OK   { param([string]$msg) Write-Host "  OK  $msg" -ForegroundColor Green }
function Write-Warn { param([string]$msg) Write-Host "  !!  $msg" -ForegroundColor Yellow }

$CbRoot = "C:\Program Files\Cloudbase Solutions\Cloudbase-Init"
$CbConf = Join-Path $CbRoot "conf"

# ── 1. Download the official Cloudbase-Init MSI ──────────────────────────────
Write-Step "Download Cloudbase-Init (official stable x64)"
$msiUrl = "https://www.cloudbase.it/downloads/CloudbaseInitSetup_Stable_x64.msi"
$msi    = Join-Path $env:TEMP "CloudbaseInitSetup_Stable_x64.msi"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ok = $false
for ($i = 1; $i -le 3 -and -not $ok; $i++) {
    try {
        Invoke-WebRequest -Uri $msiUrl -OutFile $msi -UseBasicParsing -TimeoutSec 120
        $ok = $true
    } catch {
        Write-Warn "Download attempt $i failed: $($_.Exception.Message)"
        Start-Sleep -Seconds 5
    }
}
if (-not $ok) { throw "Could not download Cloudbase-Init MSI from $msiUrl" }
Write-OK "Downloaded to $msi"

# ── 2. Silent install (no auto-sysprep — we seal separately) ─────────────────
Write-Step "Install Cloudbase-Init"
# /qn = silent; RUN_SERVICE_AS_LOCAL_SYSTEM=1 so the service can apply config.
# We do NOT pass the sysprep option — cleanup-windows.ps1 owns sealing.
$p = Start-Process msiexec.exe -Wait -PassThru -ArgumentList `
    "/i `"$msi`" /qn /norestart RUN_SERVICE_AS_LOCAL_SYSTEM=1 LOGGINGSERIALPORTNAME="
if ($p.ExitCode -ne 0) { throw "msiexec returned exit code $($p.ExitCode)" }
Write-OK "Cloudbase-Init installed"

# ── 3. Configuration — ConfigDrive2 (Proxmox default for Windows ostype) ─────
Write-Step "Write Cloudbase-Init configuration (ConfigDrive2)"
New-Item -ItemType Directory -Force -Path $CbConf | Out-Null

# Main config — run by the Cloudbase-Init SERVICE on first boot: creates the
# admin user, sets password, injects SSH keys, applies network + hostname.
$mainConf = @"
[DEFAULT]
username=Admin
groups=Administrators
inject_user_password=true
first_logon_behaviour=no
rename_admin_user=false
config_drive_types=iso,vfat
config_drive_locations=cdrom,hdd,partition
metadata_services=cloudbaseinit.metadata.services.configdrive.ConfigDriveService
plugins=cloudbaseinit.plugins.common.mtu.MTUPlugin,
 cloudbaseinit.plugins.common.sethostname.SetHostNamePlugin,
 cloudbaseinit.plugins.windows.createuser.CreateUserPlugin,
 cloudbaseinit.plugins.common.setuserpassword.SetUserPasswordPlugin,
 cloudbaseinit.plugins.common.sshpublickeys.SetUserSSHPublicKeysPlugin,
 cloudbaseinit.plugins.common.networkconfig.NetworkConfigPlugin,
 cloudbaseinit.plugins.windows.extendvolumes.ExtendVolumesPlugin,
 cloudbaseinit.plugins.common.userdata.UserDataPlugin
allow_reboot=false
stop_service_on_exit=false
check_latest_version=false
verbose=true
logdir=$CbRoot\log\
logfile=cloudbase-init.log
"@
Set-Content -Path (Join-Path $CbConf "cloudbase-init.conf") -Value $mainConf -Encoding ASCII

# Specialize-pass config — run by sysprep's Unattend during specialize: sets
# hostname + network early so the machine comes up named correctly.
$unattendConf = @"
[DEFAULT]
username=Admin
groups=Administrators
inject_user_password=true
config_drive_types=iso,vfat
config_drive_locations=cdrom,hdd,partition
metadata_services=cloudbaseinit.metadata.services.configdrive.ConfigDriveService
plugins=cloudbaseinit.plugins.common.mtu.MTUPlugin,
 cloudbaseinit.plugins.common.sethostname.SetHostNamePlugin,
 cloudbaseinit.plugins.common.networkconfig.NetworkConfigPlugin
allow_reboot=true
stop_service_on_exit=false
check_latest_version=false
verbose=true
logdir=$CbRoot\log\
logfile=cloudbase-init-unattend.log
"@
Set-Content -Path (Join-Path $CbConf "cloudbase-init-unattend.conf") -Value $unattendConf -Encoding ASCII
Write-OK "Config written (ConfigDrive2; hostname/user/password/ssh/network plugins)"

# ── 4. Seed sysprep's Unattend.xml so specialize runs Cloudbase-Init ─────────
Write-Step "Stage Cloudbase-Init Unattend.xml for sysprep"
$shipped   = Join-Path $CbConf "Unattend.xml"
$sysprepXml = "C:\Windows\System32\sysprep\unattend.xml"
if (Test-Path $shipped) {
    Copy-Item $shipped $sysprepXml -Force
    Write-OK "Copied Cloudbase-Init Unattend.xml -> $sysprepXml (cleanup-windows.ps1 feeds it to sysprep)"
} else {
    Write-Warn "Shipped Unattend.xml not found at $shipped — sysprep will generalize without the Cloudbase-Init specialize hook"
}

# ── 5. Ensure the service is set to start automatically ──────────────────────
$svc = Get-Service -Name cloudbase-init -ErrorAction SilentlyContinue
if ($svc) {
    Set-Service -Name cloudbase-init -StartupType Automatic
    Write-OK "cloudbase-init service set to Automatic (runs on first boot after clone)"
} else {
    Write-Warn "cloudbase-init service not found after install — check the MSI"
}

Write-OK "Cloudbase-Init ready — clones will pick up identity from the Proxmox ConfigDrive"
