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
    # Reads a plain (non-secret) value out of a .pkrvars.hcl file -- quoted
    # strings (admin_username = "it-admin") or bare tokens like numbers
    # (proxmox_vm_id = 9002). Used only for non-sensitive values -- never
    # for anything that should stay secret.
    param([string]$FilePath, [string]$VarName, [string]$Default)

    if (-not (Test-Path $FilePath)) { return $Default }
    $match = Select-String -Path $FilePath -Pattern "^\s*$VarName\s*=\s*`"?([^`"\r\n]+?)`"?\s*$" | Select-Object -First 1
    if ($match -and $match.Matches[0].Groups[1].Success -and $match.Matches[0].Groups[1].Value) {
        return $match.Matches[0].Groups[1].Value.Trim()
    }
    return $Default
}

function Get-LayeredPkrVarValue {
    # Mirrors Packer's own -var-file precedence for this build:
    #   -var-file="../../environments/homelab.pkrvars.hcl"
    #   -var-file="automation-toolbox.pkrvars.hcl"
    # (later file wins), so this script's fallback values for the post-build
    # clone step always match whatever `packer build` actually just used.
    param([string]$VarName, [string]$Default)

    $toolboxFile = Join-Path $TemplateDir "automation-toolbox.pkrvars.hcl"
    $homelabFile = Join-Path $TemplateDir "..\..\environments\homelab.pkrvars.hcl"

    $value = Get-PkrVarValue -FilePath $toolboxFile -VarName $VarName -Default ""
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }

    $value = Get-PkrVarValue -FilePath $homelabFile -VarName $VarName -Default ""
    if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }

    return $Default
}

function Invoke-ProxmoxApi {
    # Thin Invoke-RestMethod wrapper that tolerates the Proxmox host's
    # self-signed cert (the same thing Packer's own insecure_skip_tls_verify
    # = true does) on both Windows PowerShell 5.1 and PowerShell 7+, since
    # -SkipCertificateCheck only exists on 7+.
    param(
        [string]$Uri,
        [string]$Method = "GET",
        [hashtable]$Headers = @{},
        [object]$Body = $null
    )

    if ($PSVersionTable.PSVersion.Major -ge 6) {
        # -SkipHeaderValidation: PS7's HttpClient rejects Proxmox's
        # 'PVEAPIToken=user!id=secret' Authorization format before sending.
        if ($Body) {
            return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $Headers -Body $Body -SkipCertificateCheck -SkipHeaderValidation
        }
        return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $Headers -SkipCertificateCheck -SkipHeaderValidation
    }

    # Windows PowerShell 5.1 has no -SkipCertificateCheck -- fall back to a
    # process-wide certificate validation bypass instead.
    if (-not ("TrustAllCertsPolicy" -as [type])) {
        Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint sp, X509Certificate cert, WebRequest req, int problem) {
        return true;
    }
}
"@
    }
    [System.Net.ServicePointManager]::CertificatePolicy   = New-Object TrustAllCertsPolicy
    [System.Net.ServicePointManager]::SecurityProtocol    = [System.Net.SecurityProtocolType]::Tls12

    if ($Body) {
        return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $Headers -Body $Body
    }
    return Invoke-RestMethod -Uri $Uri -Method $Method -Headers $Headers
}

function Wait-ProxmoxTask {
    # Proxmox's clone/start/delete calls are async -- each returns a task ID
    # (UPID) immediately, not a result. This polls until the task reports
    # stopped, and throws if it didn't exit cleanly.
    param(
        [string]$ProxmoxUrl,
        [string]$ProxmoxNode,
        [string]$Upid,
        [hashtable]$AuthHeaders,
        [int]$TimeoutSeconds = 300
    )

    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        $status = Invoke-ProxmoxApi -Uri "$ProxmoxUrl/nodes/$ProxmoxNode/tasks/$Upid/status" -Headers $AuthHeaders
        if ($status.data.status -eq "stopped") {
            if ($status.data.exitstatus -ne "OK") {
                throw "Proxmox task $Upid finished with exitstatus '$($status.data.exitstatus)' (expected OK)"
            }
            return
        }
        Start-Sleep -Seconds 3
        $elapsed += 3
    }
    throw "Proxmox task $Upid did not finish within $TimeoutSeconds seconds"
}

function Invoke-ProxmoxCloneAndStart {
    # Clones the just-built template into a real, running VM: authenticate,
    # ask Proxmox for a free VMID (avoids guessing a number that might
    # collide with your existing scheme), full-clone, then start it.
    # cloud-init (see cloud_init=true in the .pkr.hcl source block) sets the
    # guest hostname to match $NewVmName automatically on first boot.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '',
        Justification = 'Value must be plaintext for the Proxmox REST body / bootstrap env-file; it is collected securely via Read-Host -AsSecureString upstream.')]
    param(
        [string]$ProxmoxUrl,
        [string]$ProxmoxNode,
        [string]$ProxmoxUsername,
        [string]$ProxmoxPassword,
        [int]$TemplateVmId,
        [string]$NewVmName
    )

    Write-Step "Authenticating to Proxmox API..."
    $ticketResp = Invoke-ProxmoxApi -Uri "$ProxmoxUrl/access/ticket" -Method Post -Body @{
        username = $ProxmoxUsername
        password = $ProxmoxPassword
    }
    $ticket = $ticketResp.data.ticket
    $csrf   = $ticketResp.data.CSRFPreventionToken
    if (-not $ticket) { throw "Proxmox authentication did not return a ticket -- check proxmox_username/proxmox_password" }
    Write-OK "Authenticated to $ProxmoxUrl"

    $authHeaders  = @{ Cookie = "PVEAuthCookie=$ticket" }
    $writeHeaders = @{ Cookie = "PVEAuthCookie=$ticket"; CSRFPreventionToken = $csrf }

    Write-Step "Requesting a free VMID..."
    $nextIdResp = Invoke-ProxmoxApi -Uri "$ProxmoxUrl/cluster/nextid" -Headers $authHeaders
    $newVmId = $nextIdResp.data
    Write-OK "Assigned VMID $newVmId"

    Write-Step "Cloning VMID $TemplateVmId -> $newVmId ('$NewVmName')..."
    $cloneUpid = Invoke-ProxmoxApi -Uri "$ProxmoxUrl/nodes/$ProxmoxNode/qemu/$TemplateVmId/clone" -Method Post -Headers $writeHeaders -Body @{
        newid = $newVmId
        name  = $NewVmName
        full  = 1
    }
    Wait-ProxmoxTask -ProxmoxUrl $ProxmoxUrl -ProxmoxNode $ProxmoxNode -Upid $cloneUpid.data -AuthHeaders $authHeaders -TimeoutSeconds 600
    Write-OK "Clone complete -- VMID $newVmId ('$NewVmName') created"

    Write-Step "Starting VMID $newVmId..."
    $startUpid = Invoke-ProxmoxApi -Uri "$ProxmoxUrl/nodes/$ProxmoxNode/qemu/$newVmId/status/start" -Method Post -Headers $writeHeaders
    Wait-ProxmoxTask -ProxmoxUrl $ProxmoxUrl -ProxmoxNode $ProxmoxNode -Upid $startUpid.data -AuthHeaders $authHeaders -TimeoutSeconds 120
    Write-OK "VMID $newVmId is running"
    Write-Host "  cloud-init will set the guest hostname to '$NewVmName' a few seconds after boot completes." -ForegroundColor DarkGray

    return @{ VmId = [int]$newVmId; AuthHeaders = $authHeaders; WriteHeaders = $writeHeaders }
}

function Wait-ProxmoxGuestAgent {
    # Polls the QEMU guest agent until the VM reports a usable IPv4 address.
    # The agent typically comes up 30-90s after the VM starts booting.
    param(
        [string]$ProxmoxUrl, [string]$ProxmoxNode, [int]$VmId,
        [hashtable]$AuthHeaders, [int]$TimeoutSeconds = 300
    )
    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        try {
            $r = Invoke-ProxmoxApi -Uri "$ProxmoxUrl/nodes/$ProxmoxNode/qemu/$VmId/agent/network-get-interfaces" -Headers $AuthHeaders
            foreach ($iface in $r.data.result) {
                if ($iface.name -eq 'lo') { continue }
                $addrsProp = $iface.PSObject.Properties['ip-addresses']
                if ($addrsProp -and $addrsProp.Value) {
                    foreach ($a in $addrsProp.Value) {
                        if ($a.'ip-address-type' -eq 'ipv4' -and $a.'ip-address' -notlike '127.*') {
                            return $a.'ip-address'
                        }
                    }
                }
            }
        } catch { }  # agent not up yet -- keep waiting
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
    throw "QEMU guest agent did not report an IPv4 address within $TimeoutSeconds seconds"
}

function Invoke-ProxmoxGuestExec {
    # Runs a command inside the guest via the QEMU agent (no SSH involved)
    # and returns @{ exitcode; out; err }. The 'command' parameter must be
    # sent as REPEATED form fields, which Invoke-RestMethod's hashtable
    # body cannot produce -- so the body is built by hand.
    param(
        [string]$ProxmoxUrl, [string]$ProxmoxNode, [int]$VmId,
        [hashtable]$WriteHeaders, [hashtable]$AuthHeaders,
        [string[]]$Command, [int]$TimeoutSeconds = 600
    )
    $body = ($Command | ForEach-Object { "command=" + [uri]::EscapeDataString($_) }) -join "&"
    $execResp = Invoke-ProxmoxApi -Uri "$ProxmoxUrl/nodes/$ProxmoxNode/qemu/$VmId/agent/exec" -Method Post -Headers $WriteHeaders -Body $body
    $procId = $execResp.data.pid
    if (-not $procId) { throw "agent/exec did not return a pid" }

    $elapsed = 0
    while ($elapsed -lt $TimeoutSeconds) {
        Start-Sleep -Seconds 5
        $elapsed += 5
        $st = Invoke-ProxmoxApi -Uri "$ProxmoxUrl/nodes/$ProxmoxNode/qemu/$VmId/agent/exec-status?pid=$procId" -Headers $AuthHeaders
        if ($st.data.exited -eq 1) {
            $out = ""; $err = ""; $ec = 0
            $p = $st.data.PSObject.Properties['out-data'];  if ($p -and $p.Value) { $out = $p.Value }
            $p = $st.data.PSObject.Properties['err-data'];  if ($p -and $p.Value) { $err = $p.Value }
            $p = $st.data.PSObject.Properties['exitcode'];  if ($p) { $ec = [int]$p.Value }
            return @{ exitcode = $ec; out = $out; err = $err }
        }
    }
    throw "Guest command did not finish within $TimeoutSeconds seconds"
}

function ConvertTo-ShellSingleQuoted {
    # Safely single-quotes a value for a POSIX shell env file.
    param([string]$Value)
    return "'" + ($Value -replace "'", "'\''") + "'"
}

function Invoke-ToolboxBootstrap {
    # Drives scripts/bootstrap-toolbox.sh inside the freshly cloned VM via
    # the QEMU guest agent: waits for an IP, delivers the answers as a
    # root-only env file (deleted by the guest as it runs), executes the
    # bootstrap non-interactively, and streams its output back.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '',
        Justification = 'Value must be plaintext for the Proxmox REST body / bootstrap env-file; it is collected securely via Read-Host -AsSecureString upstream.')]
    param(
        [string]$ProxmoxUrl, [string]$ProxmoxNode, [int]$VmId,
        [hashtable]$WriteHeaders, [hashtable]$AuthHeaders,
        [string]$SemaphorePassword, [string]$PveHost, [string]$PveUser,
        [string]$TokenId, [string]$TokenSecret, [string]$PvePassword,
        [string]$MgmtSubnet, [bool]$AutoBuildGolden = $false,
        [string]$WinrmPassword = "",
        [string]$AdminUser = "", [string]$AdminPassword = ""
    )

    Write-Step "Waiting for the new VM to report an IP (guest agent)..."
    $ip = Wait-ProxmoxGuestAgent -ProxmoxUrl $ProxmoxUrl -ProxmoxNode $ProxmoxNode -VmId $VmId -AuthHeaders $AuthHeaders
    Write-OK "VM is up at $ip"

    Write-Step "Delivering bootstrap answers to the guest..."
    $lines = @(
        "SEMAPHORE_ADMIN_PASS=$(ConvertTo-ShellSingleQuoted $SemaphorePassword)"
        "PROXMOX_HOST=$(ConvertTo-ShellSingleQuoted $PveHost)"
        "PROXMOX_USER=$(ConvertTo-ShellSingleQuoted $PveUser)"
        "PROXMOX_NODE=$(ConvertTo-ShellSingleQuoted $ProxmoxNode)"
    )
    if ($TokenId) {
        $lines += "PROXMOX_TOKEN_ID=$(ConvertTo-ShellSingleQuoted $TokenId)"
        $lines += "PROXMOX_TOKEN_SECRET=$(ConvertTo-ShellSingleQuoted $TokenSecret)"
    } elseif ($PvePassword) {
        $lines += "PROXMOX_PASSWORD=$(ConvertTo-ShellSingleQuoted $PvePassword)"
    }
    if ($MgmtSubnet) { $lines += "MGMT_SUBNET=$(ConvertTo-ShellSingleQuoted $MgmtSubnet)" }
    if ($WinrmPassword) { $lines += "WINRM_PASSWORD=$(ConvertTo-ShellSingleQuoted $WinrmPassword)" }
    if ($AdminUser)     { $lines += "DEPLOY_ADMIN_USER=$(ConvertTo-ShellSingleQuoted $AdminUser)" }
    if ($AdminPassword) { $lines += "DEPLOY_ADMIN_PASSWORD=$(ConvertTo-ShellSingleQuoted $AdminPassword)" }
    if ($AutoBuildGolden) { $lines += "AUTO_BUILD_GOLDEN='1'" }
    $envContent = ($lines -join "`n") + "`n"
    $fwBody = "file=" + [uri]::EscapeDataString("/root/.bootstrap-env") + "&content=" + [uri]::EscapeDataString($envContent)
    Invoke-ProxmoxApi -Uri "$ProxmoxUrl/nodes/$ProxmoxNode/qemu/$VmId/agent/file-write" -Method Post -Headers $WriteHeaders -Body $fwBody | Out-Null

    Write-Step "Running bootstrap inside the guest..."
    $guestCmd = 'chmod 600 /root/.bootstrap-env; set -a; . /root/.bootstrap-env; set +a; rm -f /root/.bootstrap-env; ' +
                'export BOOTSTRAP_NONINTERACTIVE=1; ' +
                'bash /git/monorepo/automation/packer/builds/ubuntu-2404-automation-toolbox/scripts/bootstrap-toolbox.sh'
    $result = Invoke-ProxmoxGuestExec -ProxmoxUrl $ProxmoxUrl -ProxmoxNode $ProxmoxNode -VmId $VmId `
        -WriteHeaders $WriteHeaders -AuthHeaders $AuthHeaders -Command @("bash", "-c", $guestCmd)

    if ($result.out) { $result.out -split "`n" | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray } }
    if ($result.err) { $result.err -split "`n" | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow } }
    if ($result.exitcode -ne 0) { throw "Bootstrap exited with code $($result.exitcode) -- see output above" }

    Write-OK "Bootstrap complete -- toolbox is fully operational"
    Write-Host ""
    Write-Host "    Semaphore : http://$ip/        (login: admin)"  -ForegroundColor Green
    Write-Host "    Homepage  : http://${ip}:3002/"                 -ForegroundColor Green
    Write-Host "    Webmin    : https://${ip}:10000/"               -ForegroundColor Green
    return $ip
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
$sharedPassword = ""

$AdminUsername = Get-PkrVarValue `
    -FilePath "$TemplateDir\automation-toolbox.pkrvars.hcl" `
    -VarName  "admin_username" `
    -Default  "the admin account"

try {
    $proxmoxPassword        = Resolve-RequiredVar "PKR_VAR_proxmox_password"         "What's the password for your Proxmox host (root or API user)?"

    # Fast-path: one password for every account (Semaphore/Portainer, the VM
    # admin, and WinRM). Handy for initial builds — rotate later with a secrets
    # manager. Must be 12+ chars (Portainer's minimum). Skipped if the Semaphore
    # password is already provided via PKR_VAR_semaphore_admin_password.
    if (-not $env:PKR_VAR_semaphore_admin_password) {
        Write-Host ""
        $ans = Read-Host "  Use ONE password for ALL accounts (Semaphore/Portainer, $AdminUsername, WinRM)? (y/N)"
        if ($ans -match '^[Yy]') {
            while ($sharedPassword.Length -lt 12) {
                $secure = Read-Host "  Shared password for all accounts (12+ chars, input hidden)" -AsSecureString
                $sharedPassword = [System.Net.NetworkCredential]::new("", $secure).Password
                if ($sharedPassword.Length -lt 12) { Write-Host "  12 or more characters required." -ForegroundColor Red }
            }
            Write-Host "  Using one shared password for all accounts." -ForegroundColor Green
        }
    }

    if ($sharedPassword) {
        $semaphoreAdminPassword = $sharedPassword
        $adminPassword          = $sharedPassword
    } else {
    # Semaphore + Portainer share this login; Portainer enforces 12+ chars.
    $semaphoreAdminPassword = $env:PKR_VAR_semaphore_admin_password
    while ([string]::IsNullOrWhiteSpace($semaphoreAdminPassword) -or $semaphoreAdminPassword.Length -lt 12) {
        if ($semaphoreAdminPassword -and $semaphoreAdminPassword.Length -lt 12) {
            Write-Host "  That password is $($semaphoreAdminPassword.Length) characters — 12 or more required (Portainer's minimum)." -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "  Choose the admin password for the web UIs (Semaphore AND Portainer)." -ForegroundColor Yellow
        Write-Host "  Requirements: 12+ characters. Press Enter to use the default" -ForegroundColor Yellow
        Write-Host "  'Change-Me-Toolbox!' — easy to remember, change it after first login" -ForegroundColor Yellow
        Write-Host "  (Semaphore: top-right user menu; Portainer: user settings)." -ForegroundColor Yellow
        $secure = Read-Host "  Admin password [Change-Me-Toolbox!] (input hidden)" -AsSecureString
        $semaphoreAdminPassword = [System.Net.NetworkCredential]::new("", $secure).Password
        if ([string]::IsNullOrWhiteSpace($semaphoreAdminPassword)) { $semaphoreAdminPassword = "Change-Me-Toolbox!" }
    }
    $adminPassword          = Resolve-OptionalVar "PKR_VAR_admin_password"           "Choose a password for the '$AdminUsername' login on the built VM. You can also just use your SSH key and leave this blank."

    # A blank admin password silently produces a server that refuses password
    # SSH — that has bitten before. Make key-only an explicit choice.
    while (-not $adminPassword) {
        Write-Host ""
        Write-Host "  No admin password set: '$AdminUsername' will be SSH-KEY-ONLY (password login refused, console login unavailable)." -ForegroundColor Yellow
        $ans = Read-Host "  Type 'key-only' to confirm that, or press Enter to set a password now"
        if ($ans -eq 'key-only') { break }
        $secure        = Read-Host "  Password for '$AdminUsername' (input hidden)" -AsSecureString
        $adminPassword = [System.Net.NetworkCredential]::new("", $secure).Password
    }
    }
} catch {
    Write-Fail $_.Exception.Message
    exit 1
}
Write-OK "Credentials ready"

# Non-secret Proxmox connection details, read from the same var files Packer
# itself uses -- needed for the optional post-build clone step below.
$ProxmoxUrlValue      = Get-LayeredPkrVarValue -VarName "proxmox_url"      -Default "https://192.168.1.10:8006/api2/json"
$ProxmoxNodeValue     = Get-LayeredPkrVarValue -VarName "proxmox_node"     -Default "pve"
$ProxmoxUsernameValue = Get-LayeredPkrVarValue -VarName "proxmox_username" -Default "root@pam"
$ProxmoxTemplateVmId  = [int](Get-LayeredPkrVarValue -VarName "proxmox_vm_id" -Default "9002")

# ── Deployment answers, collected up-front so the whole run is hands-off ─────
$deployAfterBuild = $false
$vmName = "POSLXPDEPLOY01"; $pveTokenId = ""; $pveTokenSecret = ""; $pveTokenUser = ""; $mgmtSubnet = ""; $winrmPassword = ""; $autoBuildGolden = $false
if (-not $DryRun) {
    Write-Host ""
    Write-Host "  After the build this script can clone the template, start the VM and" -ForegroundColor Yellow
    Write-Host "  bootstrap it into a fully working toolbox -- zero touch." -ForegroundColor Yellow
    $ans = Read-Host "  Deploy + bootstrap automatically after the build? (Y/n)"
    $deployAfterBuild = ($ans -notmatch '^[Nn]')
    if ($deployAfterBuild) {
        $v = Read-Host "  New VM name [$vmName]"
        if (-not [string]::IsNullOrWhiteSpace($v)) { $vmName = $v.Trim() }
        Write-Host ""
        Write-Host "  A Proxmox API token (recommended) powers Semaphore's provisioning jobs and the" -ForegroundColor DarkGray
        Write-Host "  dashboard's live Proxmox widget. Create one: Datacenter -> Permissions -> API Tokens" -ForegroundColor DarkGray
        Write-Host "  -- give it privileges (or untick Privilege Separation). Skipping falls back to the" -ForegroundColor DarkGray
        Write-Host "  Proxmox password for provisioning; the dashboard widget then needs a token later." -ForegroundColor DarkGray
        $pveTokenId = (Read-Host "  Proxmox API token ID (Enter = skip)").Trim()
        if ($pveTokenId) {
            $u = (Read-Host "  Which user OWNS this token? [$ProxmoxUsernameValue]").Trim()
            if ($u) { $pveTokenUser = $u } else { $pveTokenUser = $ProxmoxUsernameValue }
            $sec = Read-Host "  Token secret (input hidden)" -AsSecureString
            $pveTokenSecret = [System.Net.NetworkCredential]::new("", $sec).Password
            # Validate NOW — a user/token mismatch would otherwise surface as
            # 401s in Semaphore jobs and the dashboard after a 30-min build.
            # NB: hidden input can silently mangle PASTED secrets in some
            # consoles — if validation keeps failing with a known-good token,
            # that is the usual culprit. 'skip' bypasses validation.
            while ($true) {
                # strip whitespace/control chars that clipboard paste can inject
                $pveTokenSecret = ($pveTokenSecret -replace '[\x00-\x1f]', '').Trim()
                try {
                    Invoke-ProxmoxApi -Uri "$ProxmoxUrlValue/version" -Headers @{
                        Authorization = "PVEAPIToken=$pveTokenUser!$pveTokenId=$pveTokenSecret"
                    } | Out-Null
                    Write-Host "  Token verified for $pveTokenUser!$pveTokenId" -ForegroundColor Green
                    break
                } catch {
                    Write-Host "  Validation failed for '$pveTokenUser!$pveTokenId' against $ProxmoxUrlValue/version" -ForegroundColor Red
                    Write-Host "  Underlying error: $($_.Exception.Message)" -ForegroundColor Red
                    Write-Host "  (401 = wrong owner user or secret; timeouts/TLS errors = URL problem, not the token." -ForegroundColor DarkGray
                    Write-Host "   Secrets pasted into hidden prompts are sometimes mangled — type 'visible' to enter it non-hidden.)" -ForegroundColor DarkGray
                    $u = (Read-Host "  Token owner user [$pveTokenUser] ('skip' = proceed unvalidated)").Trim()
                    if ($u -eq 'skip') { Write-Host "  Skipping validation — proceeding with the values as entered." -ForegroundColor Yellow; break }
                    if ($u -eq 'visible') {
                        $pveTokenSecret = (Read-Host "  Token secret (VISIBLE)").Trim()
                        continue
                    }
                    if ($u) { $pveTokenUser = $u }
                    $sec = Read-Host "  Token secret (Enter = keep current, input hidden)" -AsSecureString
                    $ts = [System.Net.NetworkCredential]::new("", $sec).Password
                    if ($ts) { $pveTokenSecret = $ts }
                }
            }
        }
        $mgmtSubnet = (Read-Host "  Management subnet for firewall lockdown, e.g. 192.168.4.0/24 (Enter = skip)").Trim()
        if ($sharedPassword) {
            $winrmPassword = $sharedPassword
        } else {
            $sec = Read-Host "  WinRM password for Windows golden builds (Enter = skip; injected into the unattended install automatically)" -AsSecureString
            $winrmPassword = [System.Net.NetworkCredential]::new("", $sec).Password
        }
        $ans = Read-Host "  Build the golden image templates right after bootstrap (Ubuntu 24.04 + 26.04, and Windows if its ISO is present)? (Y/n)"
        $autoBuildGolden = ($ans -notmatch '^[Nn]')
    }
}

# ── Toolbox sizing (defaults suit modest hosts; more is better if you have it) ─
$vmCpu = 4; $vmMemMb = 8192
if (-not $DryRun) {
    Write-Host ""
    Write-Host "  Toolbox VM sizing: default 4 vCPU / 8 GB RAM — fine for the core services." -ForegroundColor Yellow
    Write-Host "  8 vCPU / 16 GB is recommended if your host has capacity (needed comfort once" -ForegroundColor DarkGray
    Write-Host "  NetBox and Prometheus/Grafana are deployed onto this server later)." -ForegroundColor DarkGray
    $v = Read-Host "  vCPU count [4]"
    if ($v -match '^\d+$' -and [int]$v -ge 1) { $vmCpu = [int]$v }
    $v = Read-Host "  Memory in GB [8]"
    if ($v -match '^\d+$' -and [int]$v -ge 2) { $vmMemMb = [int]$v * 1024 }
    Write-Host "  Sizing: $vmCpu vCPU / $($vmMemMb/1024) GB" -ForegroundColor Green
}

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
    $varArgs = @($VarFiles | ForEach-Object { "-var-file=$_" })
    $varArgs += @("-var", "vm_cpu_count=$vmCpu", "-var", "vm_memory_mb=$vmMemMb")
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

        # ── Step 6: Clone + bootstrap — the hands-off deployment ──
        if ($deployAfterBuild) {
            try {
                $deploy = Invoke-ProxmoxCloneAndStart `
                    -ProxmoxUrl      $ProxmoxUrlValue `
                    -ProxmoxNode     $ProxmoxNodeValue `
                    -ProxmoxUsername $ProxmoxUsernameValue `
                    -ProxmoxPassword $proxmoxPassword `
                    -TemplateVmId    $ProxmoxTemplateVmId `
                    -NewVmName       $vmName

                $pveApiHost = ([uri]$ProxmoxUrlValue).Host
                $bootstrapUser = if ($pveTokenUser) { $pveTokenUser } else { $ProxmoxUsernameValue }
                Invoke-ToolboxBootstrap `
                    -ProxmoxUrl        $ProxmoxUrlValue `
                    -ProxmoxNode       $ProxmoxNodeValue `
                    -VmId              $deploy.VmId `
                    -WriteHeaders      $deploy.WriteHeaders `
                    -AuthHeaders       $deploy.AuthHeaders `
                    -SemaphorePassword $semaphoreAdminPassword `
                    -PveHost           $pveApiHost `
                    -PveUser           $bootstrapUser `
                    -TokenId           $pveTokenId `
                    -TokenSecret       $pveTokenSecret `
                    -PvePassword       $proxmoxPassword `
                    -MgmtSubnet        $mgmtSubnet `
                    -AutoBuildGolden   $autoBuildGolden `
                    -WinrmPassword     $winrmPassword `
                    -AdminUser         $AdminUsername `
                    -AdminPassword     $adminPassword | Out-Null
            } catch {
                Write-Fail "Deployment failed: $($_.Exception.Message)"
                Write-Host "  The template itself is unaffected. Retry: clone it in Proxmox, then run" -ForegroundColor DarkGray
                Write-Host "  sudo /git/monorepo/automation/packer/builds/ubuntu-2404-automation-toolbox/scripts/bootstrap-toolbox.sh on the VM." -ForegroundColor DarkGray
            }
        } else {
            Write-Host "  Skipping deployment -- clone the template in Proxmox, then run the bootstrap on the VM." -ForegroundColor DarkGray
        }
    }
} catch {
    Write-Fail $_.Exception.Message
    exit 1
} finally {
    # Packer's manifest post-processor leaves this lock file behind; it has
    # no purpose after the build finishes and was showing up as an
    # unexpected "modified/untracked" file in git/VS Code. Safe to remove
    # unconditionally -- it's regenerated fresh on the next build.
    $LockFile = Join-Path $TemplateDir "packer-manifest-automation-toolbox.json.lock"
    if (Test-Path $LockFile) { Remove-Item $LockFile -Force -ErrorAction SilentlyContinue }

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
