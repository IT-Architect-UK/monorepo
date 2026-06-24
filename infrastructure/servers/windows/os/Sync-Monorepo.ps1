<#
.SYNOPSIS
    Clones or pulls the latest IT-Architect monorepo to C:\Monorepo.

.DESCRIPTION
    Registered as a Windows Scheduled Task by provision-windows.ps1 during the
    Packer build. Runs automatically:
      • On every system startup  (1-minute delay to allow network)
      • Daily at 01:00

    After the sync, all repo scripts are available under C:\Monorepo\:
      C:\Monorepo\infrastructure\servers\windows\os\
      C:\Monorepo\infrastructure\servers\windows\packages\
      C:\Monorepo\infrastructure\networking\firewall\
      C:\Monorepo\automation\ansible\
      etc.

    Failure handling:
      If GitHub is unreachable, the existing local copy is left intact and the
      error is logged. The script always exits 0 so the scheduled task does not
      report failures for transient network issues.

.NOTES
    Version:           1.0
    Author:            Darren Pilkington
    Modification Date: 2026-06-24
    Requires:          git in PATH (installed via Chocolatey), internet access
#>

$RepoUrl = "https://github.com/IT-Architect-UK/monorepo.git"
$RepoDir = "C:\Monorepo"
$LogDir  = "C:\Logs\MonorepoSync"
$LogFile = Join-Path $LogDir "monorepo-sync-$(Get-Date -Format 'yyyy-MM-dd').log"

# ── Logging ───────────────────────────────────────────────────────────────────
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level]  $Message"
    Write-Host $entry
    Add-Content -Path $LogFile -Value $entry
}

Write-Log "Monorepo sync starting on $env:COMPUTERNAME"

# ── git available? ────────────────────────────────────────────────────────────
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if (-not $gitCmd) {
    Write-Log "git not found in PATH — cannot sync. Install git (choco install git) and re-run." "WARN"
    exit 0
}
Write-Log "git found: $($gitCmd.Source)"

# ── Connectivity check ────────────────────────────────────────────────────────
try {
    $null = Invoke-WebRequest -Uri "https://github.com" -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
} catch {
    Write-Log "GitHub not reachable — skipping sync. Existing copy is unchanged." "WARN"
    exit 0
}

# ── Clone or pull ─────────────────────────────────────────────────────────────
$gitDir = Join-Path $RepoDir ".git"

if (Test-Path $gitDir) {
    Write-Log "Pulling latest changes into $RepoDir ..."
    $output = & git -C $RepoDir pull --ff-only 2>&1
    if ($LASTEXITCODE -eq 0) {
        $head = & git -C $RepoDir rev-parse --short HEAD 2>&1
        Write-Log "Pull complete. HEAD: $head"
    } else {
        Write-Log "Pull failed — recloning. Output: $output" "WARN"
        Remove-Item -Path $RepoDir -Recurse -Force -ErrorAction SilentlyContinue
        $output = & git clone --quiet $RepoUrl $RepoDir 2>&1
        if ($LASTEXITCODE -eq 0) {
            $head = & git -C $RepoDir rev-parse --short HEAD 2>&1
            Write-Log "Reclone complete. HEAD: $head"
        } else {
            Write-Log "Reclone failed. Output: $output" "ERROR"
        }
    }
} else {
    Write-Log "Cloning $RepoUrl into $RepoDir ..."
    if (-not (Test-Path $RepoDir)) {
        New-Item -ItemType Directory -Path $RepoDir -Force | Out-Null
    }
    $output = & git clone --quiet $RepoUrl $RepoDir 2>&1
    if ($LASTEXITCODE -eq 0) {
        $head = & git -C $RepoDir rev-parse --short HEAD 2>&1
        Write-Log "Clone complete. HEAD: $head"
    } else {
        Write-Log "Clone failed. Output: $output" "ERROR"
    }
}

Write-Log "Monorepo sync finished. Scripts available at: $RepoDir"
