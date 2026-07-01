# =============================================================================
# build-automation-toolbox-proxmox.ps1
# Packer build script for ubuntu-2604-automation-toolbox (Proxmox only)
#
# LOCATION: automation/packer/builds/ubuntu-2604-automation-toolbox/
#
# RECOMMENDED SETUP — avoids interactive prompts on every run:
#   Set these Windows user environment variables once in PowerShell, then
#   open a new terminal. They persist permanently and are never stored in
#   any file or committed to GitHub.
#
#     [System.Environment]::SetEnvironmentVariable("PKR_VAR_proxmox_password",         "your-value", "User")
#     [System.Environment]::SetEnvironmentVariable("PKR_VAR_semaphore_admin_password", "your-value", "User")
#     [System.Environment]::SetEnvironmentVariable("PKR_VAR_admin_password",           "your-value", "User")
#
#   If any of these is missing the script will prompt you to enter it.
#   Prompted values are used for this session only — not saved anywhere.
#
#   PKR_VAR_ssh_password is NOT prompted for — it's a temporary, build-only
#   credential pinned to the password baked into http/user-data (default:
#   "packer-temp-password"), and Packer falls back to that default on its
#   own. Only set this env var if you've regenerated the cidata ISO with a
#   different password.
#
# USAGE (from this folder in a PowerShell terminal):
#   .\build-automation-toolbox-proxmox.ps1           # Full build
#   .\build-automation-toolbox-proxmox.ps1 -DryRun   # Validate only, no build
#   .\build-automation-toolbox-proxmox.ps1 -Verbose  # Full Packer debug output
# =============================================================================

param(
    [switch]$DryRun,
    [switch]$Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Script lives inside the template dir — all paths are relative to here
$TemplateDir = $PSScriptRoot
$RepoRoot    = Resolve-Path "$TemplateDir\..\..\.."
$VarFiles    = @(
    "../../environments/homelab.pkrvars.hcl",
    "../../environments/automation-toolbox.pkrvars.hcl"
)

function Write-Step($msg) {
    Write-Host ""
    Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] >>> $msg" -ForegroundColor Cyan
}
function Write-OK($msg)   { Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))]  OK  $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] FAIL $msg" -ForegroundColor Red }

function Resolve-RequiredVar {
    param([string]$VarName, [string]$Description)

    $value = [System.Environment]::GetEnvironmentVariable($VarName)
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }

    Write-Host ""
    Write-Host "  $VarName is not set." -ForegroundColor Yellow
    Write-Host "  ($Description)" -ForegroundColor DarkGray
    Write-Host "  To avoid this prompt in future, set it permanently:" -ForegroundColor DarkGray
    Write-Host "    [System.Environment]::SetEnvironmentVariable(`"$VarName`", `"your-value`", `"User`")" -ForegroundColor DarkGray

    $secure = Read-Host "  Enter value now (input hidden)" -AsSecureString
    $plain  = [System.Net.NetworkCredential]::new("", $secure).Password

    if ([string]::IsNullOrWhiteSpace($plain)) { throw "No value entered for $VarName — aborting." }
    return $plain
}

# ── Banner ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "  Packer Build — Ubuntu 26.04 Automation Toolbox (Proxmox)" -ForegroundColor Yellow
if ($DryRun)  { Write-Host "  MODE: Validate only (no build)" -ForegroundColor Magenta }
if ($Verbose) { Write-Host "  MODE: Verbose Packer logging"   -ForegroundColor Magenta }
Write-Host "  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow

# ── Resolve credentials ───────────────────────────────────────────────────────
Write-Step "Resolving credentials..."
try {
    $proxmoxPassword        = Resolve-RequiredVar "PKR_VAR_proxmox_password"         "Proxmox root or API user password"
    $semaphoreAdminPassword = Resolve-RequiredVar "PKR_VAR_semaphore_admin_password" "Semaphore UI initial admin password"
    $adminPassword          = Resolve-RequiredVar "PKR_VAR_admin_password"           "Password for your personal admin login on the built VM"
} catch {
    Write-Fail $_.Exception.Message
    exit 1
}
Write-OK "Credentials ready"

$env:PKR_VAR_proxmox_password         = $proxmoxPassword
$env:PKR_VAR_semaphore_admin_password = $semaphoreAdminPassword
$env:PKR_VAR_admin_password           = $adminPassword
# PKR_VAR_ssh_password is intentionally left alone here — if it's already set
# in the environment it will still be picked up by Packer; otherwise Packer
# uses its own default ("packer-temp-password") from variables.pkr.hcl.

# ── Step 1: Git pull ──────────────────────────────────────────────────────────
Write-Step "Syncing monorepo from GitHub..."
Push-Location $RepoRoot
try {
    git pull origin main 2>&1 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) { throw "git pull failed" }
    Write-OK "Repo up to date"
} finally { Pop-Location }

# ── Step 2: Packer logging ────────────────────────────────────────────────────
if ($Verbose) { $env:PACKER_LOG = "1" } else { Remove-Item Env:\PACKER_LOG -ErrorAction SilentlyContinue }

# ── Steps 3–5: Init, Validate, Build (run from inside the template dir) ───────
Push-Location $TemplateDir
try {
    Write-Step "Running packer init..."
    packer init .
    if ($LASTEXITCODE -ne 0) { throw "packer init failed" }
    Write-OK "Plugins ready"

    Write-Step "Validating template..."
    $varArgs = $VarFiles | ForEach-Object { "-var-file=$_" }
    packer validate @varArgs .
    if ($LASTEXITCODE -ne 0) { throw "packer validate failed" }
    Write-OK "Template valid"

    if ($DryRun) {
        Write-Host ""
        Write-Host "  DryRun complete — skipping build." -ForegroundColor Magenta
    } else {
        Write-Step "Starting build (20–40 min)..."
        Write-Host "  Tip: watch progress in the Proxmox console." -ForegroundColor DarkGray
        Write-Host ""

        packer build @varArgs .
        if ($LASTEXITCODE -ne 0) { throw "packer build failed" }

        Write-OK "Build complete — template is ready in Proxmox."
        if (Test-Path "packer-manifest-automation-toolbox.json") {
            Write-Host "  Manifest: $TemplateDir\packer-manifest-automation-toolbox.json" -ForegroundColor DarkGray
        }
    }
} catch {
    Write-Fail $_.Exception.Message
    exit 1
} finally {
    Remove-Item Env:\PKR_VAR_proxmox_password          -ErrorAction SilentlyContinue
    Remove-Item Env:\PKR_VAR_ssh_password              -ErrorAction SilentlyContinue
    Remove-Item Env:\PKR_VAR_semaphore_admin_password  -ErrorAction SilentlyContinue
    Remove-Item Env:\PKR_VAR_admin_password            -ErrorAction SilentlyContinue
    Remove-Item Env:\PACKER_LOG                        -ErrorAction SilentlyContinue
    Pop-Location
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "  Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host ""
