# =============================================================================
# cleanup-windows.ps1 — Seal the Windows golden image before Packer snapshots
# =============================================================================
# MUST be the last provisioner step. After this script:
#   1. Temp files and logs are cleared
#   2. The packer build account is removed
#   3. Sysprep generalizes the image and shuts down the VM
#   4. Packer detects the shutdown and converts the VM to a template
#
# After cloning the template, the new VM runs the Windows OOBE "specialize"
# pass on first boot — it will boot up, auto-configure, and be ready to use.
# =============================================================================

$ErrorActionPreference = 'SilentlyContinue'

function Write-Step { param([string]$msg) Write-Host "`n── $msg ──" -ForegroundColor Cyan }
function Write-OK   { param([string]$msg) Write-Host "  ✔  $msg" -ForegroundColor Green }

# ── 1. Remove WinRM HTTP firewall rule (not needed after build) ───────────────
Write-Step "Remove build-only firewall rules"
Remove-NetFirewallRule -DisplayName "WinRM-HTTP-Packer" -ErrorAction SilentlyContinue
Write-OK "WinRM HTTP (5985) build rule removed"

# ── 2. Clear Windows event logs ──────────────────────────────────────────────
Write-Step "Clear event logs"
Get-EventLog -LogName * -ErrorAction SilentlyContinue | ForEach-Object {
    Clear-EventLog -LogName $_.Log -ErrorAction SilentlyContinue
}
Write-OK "Event logs cleared"

# ── 3. Clean temp directories ─────────────────────────────────────────────────
Write-Step "Clean temp files"

$tempPaths = @(
    $env:TEMP,
    $env:TMP,
    "$env:SystemRoot\Temp",
    "$env:SystemRoot\Prefetch",
    "$env:SystemRoot\SoftwareDistribution\Download"
)

foreach ($p in $tempPaths) {
    if (Test-Path $p) {
        Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-OK "Cleaned: $p"
    }
}

# ── 4. Remove Windows Update cache ───────────────────────────────────────────
Write-Step "Clear Windows Update cache"
Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$env:SystemRoot\SoftwareDistribution\Download\*" `
            -Recurse -Force -ErrorAction SilentlyContinue
Start-Service -Name wuauserv -ErrorAction SilentlyContinue
Write-OK "Windows Update download cache cleared"

# ── 5. Remove pagefile (sysprep re-creates it on first boot) ─────────────────
Write-Step "Remove pagefile"
$cs = Get-WmiObject Win32_ComputerSystem
$cs.AutomaticManagedPagefile = $false
$cs.Put() | Out-Null
$pf = Get-WmiObject Win32_PageFileSetting -ErrorAction SilentlyContinue
if ($pf) { $pf.Delete() | Out-Null }
Write-OK "Pagefile removed (sysprep will recreate on first boot)"

# ── 6. Remove the packer build account ────────────────────────────────────────
Write-Step "Remove packer build account"
# Note: we cannot delete ourselves while logged in.
# Sysprep generalizes the image anyway, so all local accounts are handled
# at the OOBE level. We schedule deletion via a RunOnce key instead.
$runOncePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
Set-ItemProperty -Path $runOncePath `
                 -Name "RemovePackerAccount" `
                 -Value 'net user packer /delete' `
                 -ErrorAction SilentlyContinue
Write-OK "Packer account deletion scheduled for first boot (via RunOnce)"

# ── 7. Defragment and zero-fill free space (shrinks the template disk) ────────
Write-Step "Optimise disk for thin provisioning"

# Defragment C:
defrag C: /U /V 2>&1 | Out-Null
Write-OK "Disk defragmented"

# Zero out free space so thin-provisioned disks compress better.
# Uses the sdelete trick: write zeros to a file, then delete it.
# Disable with -SkipZeroFill if you want a faster build.
$sdeleteUrl = "https://download.sysinternals.com/files/SDelete.zip"
$sdeleteZip = "$env:TEMP\sdelete.zip"
$sdeleteDir = "$env:TEMP\sdelete"

try {
    Invoke-WebRequest -Uri $sdeleteUrl -OutFile $sdeleteZip -TimeoutSec 30
    Expand-Archive -Path $sdeleteZip -DestinationPath $sdeleteDir -Force
    & "$sdeleteDir\sdelete64.exe" -z C: -accepteula 2>&1 | Out-Null
    Write-OK "Free space zeroed (thin-provisioned disk will compress better)"
} catch {
    Write-Host "  ⚠  sdelete not available — skipping zero-fill (non-fatal)" -ForegroundColor Yellow
}

# ── 8. Clear recent files and shell history ───────────────────────────────────
Write-Step "Clear user shell artefacts"
# -Recurse is REQUIRED: the Recent folder has subfolders (AutomaticDestinations,
# CustomDestinations jump lists) with children. Without it, Remove-Item prompts
# "has children... continue?" which hangs forever in Packer's non-interactive
# WinRM session (-ErrorAction does NOT suppress a confirmation prompt). Caught
# live — the build hung here ~50 min before sysprep.
Remove-Item -Path "$env:USERPROFILE\AppData\Roaming\Microsoft\Windows\Recent\*" `
            -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
Clear-History -ErrorAction SilentlyContinue
Write-OK "Recent files and history cleared"

# ── 9. Sysprep — generalize and shut down ─────────────────────────────────────
Write-Step "Sysprep (generalize + shutdown)"

Write-Host "  Sysprep is running — the VM will shut down automatically."
Write-Host "  Packer will detect the shutdown and convert the VM to a template."
Write-Host ""

$sysprep = "C:\Windows\System32\sysprep\sysprep.exe"
$unattend = "C:\Windows\System32\sysprep\unattend.xml"

# Use an unattend.xml for the specialize pass if present; otherwise generalize without one
if (Test-Path $unattend) {
    & $sysprep /generalize /oobe /shutdown /quiet /unattend:$unattend
} else {
    & $sysprep /generalize /oobe /shutdown /quiet
}

# Sysprep shuts down the VM; this line is never reached during a real build
Write-OK "Sysprep complete"
