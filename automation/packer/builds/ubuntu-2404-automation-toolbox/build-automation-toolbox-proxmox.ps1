# =============================================================================
# build-automation-toolbox-proxmox.ps1
# Packer build script for ubuntu-2404-automation-toolbox (Proxmox only)
#
# LOCATION: automation/packer/builds/ubuntu-2404-automation-toolbox/
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
#   If proxmox/semaphore is missing the script will prompt you to enter it
#   (required). The admin login password prompt is OPTIONAL — press Enter
#   to skip it and the account will just have no password (SSH key only).
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

# Git, Packer, and our own provisioning scripts all emit UTF-8 (box-drawing
# characters, checkmarks, em-dashes). Without this, piping their output
# through the pipeline below (needed to also write it to the log file)
# gets decoded using the console's legacy OEM codepage instead of UTF-8,
# turning every non-ASCII character into mojibake on screen and in the log.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding            = [System.Text.Encoding]::UTF8

# Script lives inside the template dir — all paths are relative to here
$TemplateDir = $PSScriptRoot
$RepoRoot    = Resolve-Path "$TemplateDir\..\..\.."
$VarFiles    = @(
    "../../environments/homelab.pkrvars.hcl",
    "automation-toolbox.pkrvars.hcl"
)

# Every run gets its own timestamped log — mirrors everything shown on
# screen (git pull, packer init/validate/build). Folder is gitignored.
$LogDir  = Join-Path $TemplateDir "logs"
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
$LogFile = Join-Path $LogDir "build-automation-toolbox-$(Get-Date -Format 'ddMMyyyy-HH-mm').log"

function Write-Step($msg) {
    Write-Host ""
    Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] >>> $msg" -ForegroundColor Cyan
    Add-Content -Path $LogFile -Value @("", "[$([datetime]::Now.ToString('HH:mm:ss'))] >>> $msg")
}
function Write-OK($msg) {
    Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))]  OK  $msg" -ForegroundColor Green
    Add-Content -Path $LogFile -Value "[$([datetime]::Now.ToString('HH:mm:ss'))]  OK  $msg"
}
function Write-Fail($msg) {
    Write-Host "[$([datetime]::Now.ToString('HH:mm:ss'))] FAIL $msg" -ForegroundColor Red
    Add-Content -Path $LogFile -Value "[$([datetime]::Now.ToString('HH:mm:ss'))] FAIL $msg"
}

function Resolve-RequiredVar {
    param([string]$VarName, [string]$Prompt)

    $value = [System.Environment]::GetEnvironmentVariable($VarName)
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }

    Write-Host ""
    Write-Host "  $Prompt" -ForegroundColor Yellow
    Write-Host "  (to skip this prompt next time, set $VarName as a permanent env var)" -ForegroundColor DarkGray

    $secure = Read-Host "  Enter value (input hidden)" -AsSecureString
    $plain  = [System.Net.NetworkCredential]::new("", $secure).Password

    if ([string]::IsNullOrWhiteSpace($plain)) { throw "No value entered — aborting. ($Prompt)" }
    return $plain
}

function Resolve-OptionalVar {
    param([string]$VarName, [string]$Prompt)

    $value = [System.Environment]::GetEnvironmentVariable($VarName)
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }

    Write-Host ""
    Write-Host "  $Prompt" -ForegroundColor Yellow
    Write-Host "  (optional — press Enter to skip; set $VarName as a permanent env var to skip this prompt)" -ForegroundColor DarkGray

    $secure = Read-Host "  Enter value, or press Enter to skip (input hidden)" -AsSecureString
    return [System.Net.NetworkCredential]::new("", $secure).Password
}

function Get-PkrVarValue {
    # Reads a plain (non-secret) string value out of a .pkrvars.hcl file,
    # e.g. admin_username = "it-admin". Used only for friendlier prompt text
    # -- never for anything sensitive.
    param([string]$FilePath, [string]$VarName, [string]$Default)

    if (-not (Test-Path $FilePath)) { return $Default }
    $match = Select-String -Path $FilePath -Pattern "^\s*$VarName\s*=\s*`"([^`"]*)`"" | Select-Object -First 1
    if ($match -and $match.Matches[0].Groups[1].Success -and $match.Matches[0].Groups[1].Value) {
        return $match.Matches[0].Groups[1].Value
    }
    return $Default
}

# ── Banner ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "  Packer Build — Ubuntu 24.04 Automation Toolbox (Proxmox)" -ForegroundColor Yellow
if ($DryRun)  { Write-Host "  MODE: Validate only (no build)" -ForegroundColor Magenta }
if ($Verbose) { Write-Host "  MODE: Verbose Packer logging"   -ForegroundColor Magenta }
Write-Host "  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "  Log file: $LogFile" -ForegroundColor DarkGray
Write-Host "============================================================" -ForegroundColor Yellow

Add-Content -Path $LogFile -Value @(
    "============================================================"
    "  Packer Build — Ubuntu 24.04 Automation Toolbox (Proxmox)"
    "  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "============================================================"
)

# ── Resolve credentials ───────────────────────────────────────────────────────
Write-Step "Resolving credentials..."

$AdminUsername = Get-PkrVarValue `
    -FilePath "$TemplateDir\automation-toolbox.pkrvars.hcl" `
    -VarName  "admin_username" `
    -Default  "the admin account"

try {
    $proxmoxPassword        = Resolve-RequiredVar "PKR_VAR_proxmox_password"         "What's the password for your Proxmox host (root or API user)?"
    $semaphoreAdminPassword = Resolve-RequiredVar "PKR_VAR_semaphore_admin_password" "Choose a password for the Semaphore web UI's admin login (you'll use this to log in after the build)."
    $adminPassword          = Resolve-OptionalVar "PKR_VAR_admin_password"           "Choose a password for the '$AdminUsername' login on the built VM. You can also just use your SSH key and leave this blank."
} catch {
    Write-Fail $_.Exception.Message
    exit 1
}
Write-OK "Credentials ready"

$env:PKR_VAR_proxmox_password         = $proxmoxPassword
$env:PKR_VAR_semaphore_admin_password = $semaphoreAdminPassword
if (-not [string]::IsNullOrWhiteSpace($adminPassword)) {
    $env:PKR_VAR_admin_password = $adminPassword
} else {
    Write-Host "  Skipping admin password — '$AdminUsername' will be SSH-key-only." -ForegroundColor DarkGray
}
# PKR_VAR_ssh_password is intentionally left alone here — if it's already set
# in the environment it will still be picked up by Packer; otherwise Packer
# uses its own default ("packer-temp-password") from variables.pkr.hcl.

# ── Step 1: Git pull ──────────────────────────────────────────────────────────
Write-Step "Syncing monorepo from GitHub..."
Push-Location $RepoRoot
try {
    git pull origin main 2>&1 | Tee-Object -FilePath $LogFile -Append | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) { throw "git pull failed" }
    Write-OK "Repo up to date"
} finally { Pop-Location }

# ── Step 2: Packer logging ────────────────────────────────────────────────────
if ($Verbose) { $env:PACKER_LOG = "1" } else { Remove-Item Env:\PACKER_LOG -ErrorAction SilentlyContinue }
# Strips ANSI colour codes from Packer's own output so the log file stays
# plain text instead of filling with escape-sequence garbage.
$env:PACKER_NO_COLOR = "1"

# ── Steps 3–5: Init, Validate, Build (run from inside the template dir) ───────
Push-Location $TemplateDir
try {
    Write-Step "Running packer init..."
    packer init . 2>&1 | Tee-Object -FilePath $LogFile -Append | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "packer init failed" }
    Write-OK "Plugins ready"

    Write-Step "Validating template..."
    $varArgs = $VarFiles | ForEach-Object { "-var-file=$_" }
    packer validate @varArgs . 2>&1 | Tee-Object -FilePath $LogFile -Append | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { throw "packer validate failed" }
    Write-OK "Template valid"

    if ($DryRun) {
        Write-Host ""
        Write-Host "  DryRun complete — skipping build." -ForegroundColor Magenta
    } else {
        Write-Step "Starting build (20–40 min)..."
        Write-Host "  Tip: watch progress in the Proxmox console." -ForegroundColor DarkGray
        Write-Host ""

        packer build @varArgs . 2>&1 | Tee-Object -FilePath $LogFile -Append | ForEach-Object { Write-Host $_ }
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
    Remove-Item Env:\PACKER_NO_COLOR                   -ErrorAction SilentlyContinue
    Pop-Location
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host "  Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Yellow
Write-Host "  Log file: $LogFile" -ForegroundColor DarkGray
Write-Host "============================================================" -ForegroundColor Yellow
Write-Host ""
Add-Content -Path $LogFile -Value @(
    "============================================================"
    "  Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    "============================================================"
)
