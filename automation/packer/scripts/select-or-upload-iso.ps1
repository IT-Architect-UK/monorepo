# =============================================================================
# select-or-upload-iso.ps1 — Pick an existing ISO on Proxmox storage, or
# upload one from a local folder (Windows twin of select-or-upload-iso.sh)
#
# Lists ISO-capable storages, then the ISOs on the chosen storage for
# selection — or uploads a local .iso via the Proxmox API (uses the built-in
# curl.exe for the large multipart transfer).
#
# USAGE:
#   .\select-or-upload-iso.ps1
#   .\select-or-upload-iso.ps1 -ProxmoxHost 192.168.4.150 -Storage NFS-10GB-PROXMOX-1
#
# CREDENTIALS (prompted if not set):
#   $env:PROXMOX_TOKEN_ID / $env:PROXMOX_TOKEN_SECRET   # token (recommended)
#   $env:PROXMOX_PASSWORD                               # or password
#   $env:PROXMOX_USER                                   # default root@pam
#
# OUTPUT: the chosen/uploaded volid is returned (printed last).
# =============================================================================

param(
    [string]$ProxmoxHost = $(if ($env:PROXMOX_HOST) { $env:PROXMOX_HOST } else { "192.168.4.150" }),
    [string]$Node        = $env:PROXMOX_NODE,
    [string]$Storage     = $env:ISO_STORAGE
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

# ── Authenticate ─────────────────────────────────────────────────────────────
$pveUser = if ($env:PROXMOX_USER) { $env:PROXMOX_USER } else { "root@pam" }
$script:PveHeaders = @{}
$curlAuth = @()
if ($env:PROXMOX_TOKEN_ID -and $env:PROXMOX_TOKEN_SECRET) {
    $tok = "PVEAPIToken=$pveUser!$($env:PROXMOX_TOKEN_ID)=$($env:PROXMOX_TOKEN_SECRET)"
    $script:PveHeaders = @{ Authorization = $tok }
    $curlAuth = @("-H", "Authorization: $tok")
} else {
    $pw = $env:PROXMOX_PASSWORD
    if (-not $pw) {
        $secure = Read-Host "Proxmox password for $pveUser" -AsSecureString
        $pw = [System.Net.NetworkCredential]::new("", $secure).Password
    }
    $ticket = Invoke-Pve POST "/access/ticket" @{ username = $pveUser; password = $pw }
    $script:PveHeaders = @{ Cookie = "PVEAuthCookie=$($ticket.ticket)"; CSRFPreventionToken = $ticket.CSRFPreventionToken }
    $curlAuth = @("-b", "PVEAuthCookie=$($ticket.ticket)", "-H", "CSRFPreventionToken: $($ticket.CSRFPreventionToken)")
}

if (-not $Node) { $Node = (Invoke-Pve GET "/nodes")[0].node }

# ── Storage menu ─────────────────────────────────────────────────────────────
$storages = Invoke-Pve GET "/nodes/$Node/storage?content=iso&enabled=1" | Sort-Object avail -Descending
if (-not $storages) { throw "No ISO-capable storage on node $Node" }
if (-not $Storage) {
    Write-Host "`nISO-capable storage on ${Node}:" -ForegroundColor Yellow
    $i = 1
    foreach ($s in $storages) { "{0,3}) {1,-24} {2,6:N0} GB free" -f $i, $s.storage, ($s.avail / 1GB) | Write-Host; $i++ }
    $c = Read-Host "Choose storage [1]"
    if (-not $c) { $c = 1 }
    $Storage = $storages[[int]$c - 1].storage
}
Write-Host "Storage: $Storage" -ForegroundColor Cyan

# ── ISO menu or upload ───────────────────────────────────────────────────────
$isos = @(Invoke-Pve GET "/nodes/$Node/storage/$Storage/content?content=iso" | Sort-Object volid)
Write-Host "`nISOs on ${Storage}:" -ForegroundColor Yellow
$i = 1
foreach ($iso in $isos) { "{0,3}) {1,-62} {2,5:N1} GB" -f $i, $iso.volid, ($iso.size / 1GB) | Write-Host; $i++ }
Write-Host "  u) Upload a .iso from a local folder"
$c = Read-Host "Choose an ISO, or 'u' to upload"
if ($c -match '^\d+$' -and [int]$c -ge 1 -and [int]$c -le $isos.Count) {
    Write-Output $isos[[int]$c - 1].volid
    return
}
if ($c -notmatch '^[Uu]$') { throw "Invalid choice" }

$localIso = (Read-Host "Path to local .iso file").Trim('"').Trim()
if (-not (Test-Path $localIso)) { throw "File not found: $localIso" }
$fname = [System.IO.Path]::GetFileName($localIso)
$sizeGb = "{0:N1}" -f ((Get-Item $localIso).Length / 1GB)
Write-Host "Uploading $fname ($sizeGb GB) to $Storage — this can take a while..." -ForegroundColor Cyan

$curl = Get-Command curl.exe -ErrorAction SilentlyContinue
if (-not $curl) { throw "curl.exe not found (built into Windows 10 1803+) — upload the ISO via the Proxmox UI instead" }
$resp = & $curl.Source -fsSk --max-time 7200 -X POST @curlAuth `
    -F "content=iso" -F "filename=@$localIso" `
    "https://${ProxmoxHost}:8006/api2/json/nodes/$Node/storage/$Storage/upload"
if ($LASTEXITCODE -ne 0) { throw "Upload failed (curl exit $LASTEXITCODE)" }
$upid = ($resp | ConvertFrom-Json).data
if (-not $upid) { throw "Upload did not return a task ID" }
while ($true) {
    Start-Sleep -Seconds 5
    $st = Invoke-Pve GET "/nodes/$Node/tasks/$([uri]::EscapeDataString($upid))/status"
    if ($st.status -eq "stopped") {
        if ($st.exitstatus -ne "OK") { throw "Upload task failed: $($st.exitstatus)" }
        break
    }
}
Write-Host "Upload complete." -ForegroundColor Green
Write-Output "${Storage}:iso/$fname"
