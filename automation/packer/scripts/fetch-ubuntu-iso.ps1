# =============================================================================
# fetch-ubuntu-iso.ps1 — Stage the latest Ubuntu server ISO on Proxmox storage
#
# Windows twin of fetch-ubuntu-iso.sh — same behaviour: finds the newest
# live-server ISO for a release, lets you pick an ISO-capable Proxmox storage,
# and has PROXMOX ITSELF download and checksum-verify it (server-side pull).
# Nothing large passes through this machine. Idempotent: an already-present
# ISO is detected and reused.
#
# USAGE:
#   .\fetch-ubuntu-iso.ps1 -Release 24.04
#   .\fetch-ubuntu-iso.ps1 -Release 26.04 -Storage local -ProxmoxHost 192.168.4.150
#
# CREDENTIALS (prompted if not set):
#   $env:PROXMOX_TOKEN_ID / $env:PROXMOX_TOKEN_SECRET   # token (recommended)
#   $env:PROXMOX_PASSWORD                               # or password
#   $env:PROXMOX_USER                                   # default root@pam
#
# OUTPUT: the volid (e.g. local:iso/ubuntu-24.04.2-live-server-amd64.iso) is
# the function's return value and is printed last.
# =============================================================================

param(
    [Parameter(Mandatory = $true)][ValidatePattern('^\d\d\.\d\d$')][string]$Release,
    [string]$ProxmoxHost = $(if ($env:PROXMOX_HOST) { $env:PROXMOX_HOST } else { "192.168.4.150" }),
    [string]$Node        = $env:PROXMOX_NODE,
    [string]$Storage     = $env:ISO_STORAGE
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── TLS: tolerate Proxmox's self-signed cert (PS 5.1 and 7+) ─────────────────
$IsPS7 = $PSVersionTable.PSVersion.Major -ge 6
if (-not $IsPS7) {
    if (-not ("TrustAllCertsPolicy" -as [type])) {
        Add-Type @"
using System.Net; using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(ServicePoint sp, X509Certificate c, WebRequest r, int p) { return true; }
}
"@
    }
    [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
    [System.Net.ServicePointManager]::SecurityProtocol  = [System.Net.SecurityProtocolType]::Tls12
}

function Invoke-Pve {
    param([string]$Method, [string]$Path, [object]$Body = $null)
    $req = @{ Method = $Method; Uri = "https://${ProxmoxHost}:8006/api2/json$Path"; Headers = $script:PveHeaders }
    if ($Body)  { $req.Body = $Body }
    if ($IsPS7) { $req.SkipCertificateCheck = $true }
    (Invoke-RestMethod @req).data
}

# ── 1. Discover the latest ISO ───────────────────────────────────────────────
$mirror = "https://releases.ubuntu.com/$Release"
Write-Host "Checking $mirror for the latest live-server ISO..." -ForegroundColor Cyan
$sums = (Invoke-WebRequest -Uri "$mirror/SHA256SUMS" -UseBasicParsing).Content
$isoMatches = [regex]::Matches($sums, "ubuntu-$([regex]::Escape($Release))(\.\d+)?-live-server-amd64\.iso") |
    ForEach-Object { $_.Value } | Sort-Object -Unique
if (-not $isoMatches) { throw "No live-server-amd64 ISO found at $mirror" }
$isoName = ($isoMatches | Sort-Object { [version]($_ -replace '^ubuntu-([\d.]+)-live.*$', '$1') })[-1]
$isoSha  = (($sums -split "`n") | Where-Object { $_ -like "*$isoName*" } | Select-Object -First 1).Split(' ')[0].Trim()
Write-Host "Latest: $isoName" -ForegroundColor Green

# ── 2. Authenticate ──────────────────────────────────────────────────────────
$pveUser = if ($env:PROXMOX_USER) { $env:PROXMOX_USER } else { "root@pam" }
$script:PveHeaders = @{}
if ($env:PROXMOX_TOKEN_ID -and $env:PROXMOX_TOKEN_SECRET) {
    $script:PveHeaders = @{ Authorization = "PVEAPIToken=$pveUser!$($env:PROXMOX_TOKEN_ID)=$($env:PROXMOX_TOKEN_SECRET)" }
} else {
    $pw = $env:PROXMOX_PASSWORD
    if (-not $pw) {
        $secure = Read-Host "Proxmox password for $pveUser" -AsSecureString
        $pw = [System.Net.NetworkCredential]::new("", $secure).Password
    }
    $ticket = Invoke-Pve POST "/access/ticket" @{ username = $pveUser; password = $pw }
    $script:PveHeaders = @{ Cookie = "PVEAuthCookie=$($ticket.ticket)"; CSRFPreventionToken = $ticket.CSRFPreventionToken }
}

# ── 3. Node + storage ────────────────────────────────────────────────────────
if (-not $Node) { $Node = (Invoke-Pve GET "/nodes")[0].node; Write-Host "Node not specified — using '$Node'" }
$storages = Invoke-Pve GET "/nodes/$Node/storage?content=iso&enabled=1" | Sort-Object avail -Descending
if (-not $storages) { throw "No ISO-capable storage found on node $Node" }
if (-not $Storage) {
    Write-Host "`nISO-capable storage on ${Node}:" -ForegroundColor Yellow
    $i = 1
    foreach ($s in $storages) {
        "{0,3}) {1,-20} {2,6:N0} GB free" -f $i, $s.storage, ($s.avail / 1GB) | Write-Host
        $i++
    }
    $choice = Read-Host "Choose storage [1]"
    if (-not $choice) { $choice = 1 }
    $Storage = $storages[[int]$choice - 1].storage
}
Write-Host "Target storage: $Storage" -ForegroundColor Cyan
$volid = "${Storage}:iso/$isoName"

# ── 4. Skip if present ───────────────────────────────────────────────────────
$existing = Invoke-Pve GET "/nodes/$Node/storage/$Storage/content?content=iso" | Where-Object { $_.volid -eq $volid }
if ($existing) {
    Write-Host "ISO already present — nothing to download." -ForegroundColor Green
    Write-Output $volid
    return
}

# ── 5. Server-side download ──────────────────────────────────────────────────
Write-Host "Asking Proxmox to download $isoName (~3 GB — this can take a while)..." -ForegroundColor Cyan
$upid = Invoke-Pve POST "/nodes/$Node/storage/$Storage/download-url" @{
    content = "iso"; filename = $isoName; url = "$mirror/$isoName"
    checksum = $isoSha; 'checksum-algorithm' = "sha256"
}
$elapsed = 0
while ($elapsed -lt 2700) {
    Start-Sleep -Seconds 10; $elapsed += 10
    $st = Invoke-Pve GET "/nodes/$Node/tasks/$([uri]::EscapeDataString($upid))/status"
    if ($st.status -eq "stopped") {
        if ($st.exitstatus -ne "OK") { throw "Proxmox download task failed: $($st.exitstatus)" }
        Write-Host "Download complete and checksum verified." -ForegroundColor Green
        Write-Output $volid
        return
    }
    if ($elapsed % 60 -eq 0) { Write-Host "  still downloading... (${elapsed}s)" -ForegroundColor DarkGray }
}
throw "Download did not finish within 45 minutes (task $upid)"
