# =============================================================================
# build-automation-toolbox.ps1
# Packer build script for ubuntu-2604-automation-toolbox-proxmox
#
# PREREQUISITES
#   Set these Windows user environment variables once before running.
#   They persist across sessions and are never stored in any file.
#   See README.md — "Running the Build" for full instructions.
#
#     [System.Environment]::SetEnvironmentVariable("PKR_VAR_proxmox_password",        "your-value", "User")
#     [System.Environment]::SetEnvironmentVariable("PKR_VAR_ssh_password",            "your-value", "User")
#     [System.Environment]::SetEnvironmentVariable("PKR_VAR_semaphore_admin_password","your-value", "User")
#
# USAGE (from automation/packer in a PowerShell terminal):
#   .\build-automation-toolbox.ps1           # Full build
#   .\build-automation-toolbox.ps1 -DryRun   # Validate only, no build
#   .\build-automation-toolbox.ps1 -Verbose  # Full Packer debug output
# =============================================================================

param(
    [switch]$DryRun,
    [switch]$Verbose
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = $PSScriptRoot
$RepoRoot  = Resolve-Path "$ScriptDir\..\.."
$Template  = "ubuntu-2604-automation-toolbox-proxmox.pkr.hcl"
$VarFiles  = @(
    "environments/homelab.pkrvars.hcl",
    "environments/automation-toolbox.pkrvars.hcl"
)

function Write-Step($msg) {
    Write-Host ""
    Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] >>> $msg" -ForegroundColor Cyan
}
function Write-OK($msg)   { Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))]  OK  $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] FAIL $msg" -ForegroundColor Red }

# ── Banner ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "  Packer Build — Ubuntu 26.04 Automation Toolbox (Proxmox)" -ForegroundColor Yellow
if ($DryRun)  { Write-Host "  MODE: Validate only (no build)" -ForegroundColor Magenta }
if ($Verbose) { Write-Host "  MODE: Verbose Packer logging"   -ForegroundColor Magenta }
Write-Host "  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow

# ── Check required environment variables ─────────────────────────────────────
Write-Step "Checking required environment variables..."

$required = @{
    "PKR_VAR_proxmox_password"         = "Your Proxmox root (or API user) password"
    "PKR_VAR_ssh_password"             = "Temporary SSH password used during the Packer build"
    "PKR_VAR_semaphore_admin_password" = "Semaphore UI initial admin password"
}

$missing = @()
foreach ($var in $required.Keys) {
    if (-not (Test-Path "Env:\$var") -or [string]::IsNullOrWhiteSpace((Get-Item "Env:\$var").Value)) {
        $missing += $var
    }
}

if ($missing.Count -gt 0) {
    Write-Fail "The following environment variables are not set:`n"
    foreach ($var in $missing) {
        Write-Host "  $var" -ForegroundColor Red
        Write-Host "    $($required[$var])" -ForegroundColor DarkGray
    }
    Write-Host ""
    Write-Host "  Set them as persistent Windows user variables (run once in PowerShell):" -ForegroundColor Yellow
    Write-Host ""
    foreach ($var in $missing) {
        Write-Host "  [System.Environment]::SetEnvironmentVariable(`"$var`", `"your-value`", `"User`")" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "  Then open a new PowerShell terminal and run this script again." -ForegroundColor Yellow
    Write-Host "  See README.md — 'Running the Build' for full instructions." -ForegroundColor DarkGray
    Write-Host ""
    exit 1
}

Write-OK "All required variables are set"

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

# ── Step 3–5: Init, Validate, Build ───────────────────────────────────────────
Push-Location $ScriptDir
try {
    Write-Step "Running packer init..."
    packer init $Template
    if ($LASTEXITCODE -ne 0) { throw "packer init failed" }
    Write-OK "Plugins ready"

    Write-Step "Validating template..."
    $varArgs = $VarFiles | ForEach-Object { "-var-file=$_" }
    packer validate @varArgs $Template
    if ($LASTEXITCODE -ne 0) { throw "packer validate failed" }
    Write-OK "Template valid"

    if ($DryRun) {
        Write-Host ""
        Write-Host "  DryRun complete — skipping build." -ForegroundColor Magenta
    } else {
        Write-Step "Starting build (20–40 min)..."
        Write-Host "  Tip: watch progress in the Proxmox console." -ForegroundColor DarkGray
        Write-Host ""

        packer build @varArgs $Template
        if ($LASTEXITCODE -ne 0) { throw "packer build failed" }

        Write-OK "Build complete — template is ready in Proxmox."
        if (Test-Path "packer-manifest-automation-toolbox.json") {
            Write-Host "  Manifest: $ScriptDir\packer-manifest-automation-toolbox.json" -ForegroundColor DarkGray
        }
    }
} catch {
    Write-Fail $_.Exception.Message
    exit 1
} finally {
    Remove-Item Env:\PACKER_LOG -ErrorAction SilentlyContinue
    Pop-Location
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "  Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host ""
