# =============================================================================
# cleanup-windows.ps1 — Seal the Windows golden image before Packer snapshots
# =============================================================================
# MUST be the last provisioner step. After this script:
#   1. Temp files and logs are cleared
#   2. The packer build account is removed
#   3. Sysprep generalizes the image (/quit — returns cleanly, no self-shutdown)
#   4. Packer powers the VM off and converts it to a template
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
        # Preserve Packer's own working files. Packer keeps its per-provisioner
        # helper (packer-ps-env-vars-*.ps1) and uploaded script in C:\Windows\Temp
        # and dot-sources the env-vars file when THIS script returns. Deleting it
        # mid-run is what produced the "...is not recognized" error at the end of
        # cleanup — harmless (build still succeeds) but ugly. Skipping packer-*
        # leaves that machinery intact; Packer removes it itself after the build.
        Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notlike 'packer-*' } |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Write-OK "Cleaned: $p (Packer working files preserved)"
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
$cs = Get-CimInstance -ClassName Win32_ComputerSystem
if ($cs.AutomaticManagedPagefile) {
    Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false } | Out-Null
}
Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction SilentlyContinue | Remove-CimInstance -ErrorAction SilentlyContinue
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

# ── 8b. Remove Windows.old (previous-install leftovers) ──────────────────────
Write-Step "Remove Windows.old"
if (Test-Path "C:\Windows.old") {
    # takeown/icacls first — Windows.old is owned by TrustedInstaller and a
    # plain Remove-Item can't touch it. DISM's cleanup is the supported route.
    try {
        Start-Process cmd.exe -ArgumentList '/c','takeown /F C:\Windows.old /R /A /D Y >nul 2>&1 & icacls C:\Windows.old /grant Administrators:F /T /C >nul 2>&1 & rmdir /S /Q C:\Windows.old' -Wait -NoNewWindow
    } catch {}
    if (Test-Path "C:\Windows.old") {
        Write-Warn "Windows.old still present — DISM/Disk Cleanup may be needed; not baked-in blocker"
    } else {
        Write-OK "Windows.old removed"
    }
} else {
    Write-OK "No Windows.old present"
}

# ── 8c. Sysprep pre-flight: strip provisioned AppX that blocks generalize ────
# The #1 cause of a hung/failed sysprep on Win11/Server 2025 is a provisioned
# AppX package that can't generalize. Remove per-user packages that aren't
# provisioned for all users, then de-provision the store payload. All wrapped
# so a single stubborn package can never abort the build.
Write-Step "Sysprep pre-flight — clear AppX generalize blockers"
try {
    Get-AppxPackage -AllUsers | ForEach-Object {
        try { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue } catch {}
    }
    Get-AppxProvisionedPackage -Online | ForEach-Object {
        try { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue | Out-Null } catch {}
    }
    Write-OK "Provisioned AppX packages cleared (removes the common sysprep hang)"
} catch {
    Write-Warn "AppX cleanup had issues (non-critical): $($_.Exception.Message)"
}

# ── 9. Sysprep — generalize (Packer powers off) ─────────────────────────────────────
Write-Step "Sysprep (generalize)"

Write-Host "  Sysprep will generalize the image, then Packer powers the VM"
Write-Host "  off and converts it to a template."
Write-Host ""

$sysprep = "C:\Windows\System32\sysprep\sysprep.exe"
$unattend = "C:\Windows\System32\sysprep\unattend.xml"

# Use an unattend.xml for the specialize pass if present; otherwise generalize without one
# /quit (not /shutdown): sysprep generalizes then returns control, letting this
# script and Packer's provisioner finish cleanly before Packer powers the VM
# off and templates it. (The old "packer-ps-env-vars ... not recognized" error
# was unrelated to sysprep — it was the temp-clean above deleting Packer's own
# helper file; that is fixed separately by preserving packer-* in C:\Windows\Temp.)
$sysprepArgs = @('/generalize','/oobe','/quit','/quiet')
if (Test-Path $unattend) { $sysprepArgs += "/unattend:$unattend" }
& $sysprep @sysprepArgs
Write-OK "Sysprep generalize complete — Packer will power off and seal the template"
