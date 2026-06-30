# =============================================================================
# build-automation-toolbox.ps1
# Packer build script for ubuntu-2604-automation-toolbox-proxmox
#
# CREDENTIALS
#   Copy build-automation-toolbox.vars.ps1.example to
#       build-automation-toolbox.vars.ps1
#   and fill in your passwords. That file is gitignored — it never leaves
#   your machine.
#
# USAGE (from the automation/packer directory in a PowerShell terminal):
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

$ScriptDir  = $PSScriptRoot
$RepoRoot   = Resolve-Path "$ScriptDir\..\.."
$VarsFile   = "$ScriptDir\build-automation-toolbox.vars.ps1"
$Template   = "ubuntu-2604-automation-toolbox-proxmox.pkr.hcl"
$VarFiles   = @(
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

# ── Load credentials ──────────────────────────────────────────────────────────
Write-Step "Loading credentials from vars file..."
if (-not (Test-Path $VarsFile)) {
    Write-Fail "Credentials file not found: $VarsFile"
    Write-Host ""
    Write-Host "  Create it by copying the example:" -ForegroundColor Yellow
    Write-Host "  Copy-Item build-automation-toolbox.vars.ps1.example build-automation-toolbox.vars.ps1" -ForegroundColor Yellow
    Write-Host "  Then fill in your passwords." -ForegroundColor Yellow
    exit 1
}
. $VarsFile
Write-OK "Credentials loaded (local file, not committed to GitHub)"

# ── Step 1: Git pull ──────────────────────────────────────────────────────────
Write-Step "Syncing monorepo from GitHub..."
Push-Location $RepoRoot
try {
    git pull origin main 2>&1 | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) { throw "git pull failed" }
    Write-OK "Repo up to date"
} finally { Pop-Location }

# ── Step 2: Set credentials as session env vars ───────────────────────────────
Write-Step "Setting Packer environment variables (session only)..."
$env:PKR_VAR_proxmox_password         = $ProxmoxPassword
$env:PKR_VAR_ssh_password             = $PackerSshPassword
$env:PKR_VAR_semaphore_admin_password = $SemaphoreAdminPassword
if ($Verbose) { $env:PACKER_LOG = "1" } else { Remove-Item Env:\PACKER_LOG -ErrorAction SilentlyContinue }
Write-OK "Done"

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
        Write-Host "  DryRun — skipping build." -ForegroundColor Magenta
    } else {
        Write-Step "Starting build (20–40 min)..."
        Write-Host "  Tip: watch progress in the Proxmox console." -ForegroundColor DarkGray
        Write-Host ""

        packer build @varArgs $Template
        if ($LASTEXITCODE -ne 0) { throw "packer build failed" }

        Write-OK "Build complete — template is ready in Proxmox."
        if (Test-Path "packer-manifest-automation-toolbox.json") {
            Write-Host "  Manifest written to: $ScriptDir\packer-manifest-automation-toolbox.json" -ForegroundColor DarkGray
        }
    }
} catch {
    Write-Fail $_.Exception.Message
    exit 1
} finally {
    # Always clear credentials from the session
    Remove-Item Env:\PKR_VAR_proxmox_password         -ErrorAction SilentlyContinue
    Remove-Item Env:\PKR_VAR_ssh_password             -ErrorAction SilentlyContinue
    Remove-Item Env:\PKR_VAR_semaphore_admin_password  -ErrorAction SilentlyContinue
    Remove-Item Env:\PACKER_LOG                        -ErrorAction SilentlyContinue
    Pop-Location
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "  Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host ""
