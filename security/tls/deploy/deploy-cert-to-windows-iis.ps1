#Requires -Version 5.1
<#
.SYNOPSIS
    Imports a TLS certificate into Windows and binds it to an IIS website.

.DESCRIPTION
    This script imports a PEM or PFX certificate into the Windows Certificate Store
    and assigns it to an IIS website binding. Use it when you have obtained a
    certificate from Let's Encrypt, a commercial CA, or your own internal CA.

    Certificate format notes:
    ─────────────────────────
    Windows natively works with PFX (PKCS#12) format — a single file containing
    both the certificate and private key, protected with a password.

    If you have PEM files (fullchain.pem + privkey.pem), this script will
    automatically convert them to PFX using openssl (must be installed).

.PARAMETER CertPath
    Path to the certificate file (.pfx, .pem, or fullchain.pem).

.PARAMETER KeyPath
    Path to the private key (.pem). Required only if CertPath is a PEM file.

.PARAMETER PfxPassword
    Password for the PFX file. If converting from PEM, this sets the PFX password.

.PARAMETER SiteName
    Name of the IIS website to bind the certificate to. Default: "Default Web Site"

.PARAMETER Hostname
    The hostname for the IIS binding (SNI). Required for multiple HTTPS sites on one IP.

.PARAMETER Port
    HTTPS port number. Default: 443.

.EXAMPLE
    # Import PFX certificate
    .\deploy-cert-to-windows-iis.ps1 -CertPath "C:\certs\example.pfx" -PfxPassword "secret" -Hostname "example.com"

.EXAMPLE
    # Convert PEM → PFX, then import
    .\deploy-cert-to-windows-iis.ps1 -CertPath "fullchain.pem" -KeyPath "privkey.pem" -Hostname "example.com"

.NOTES
    Prerequisites:
    - IIS installed (Web-Server feature)
    - WebAdministration PowerShell module (part of IIS)
    - openssl.exe in PATH (only needed for PEM conversion)

    Author  : IT-Architect-UK
    Repo    : https://github.com/IT-Architect-UK/monorepo
    Version : 1.0.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$CertPath,
    [Parameter()]          [string]$KeyPath,
    [Parameter()]          [string]$PfxPassword = "TempPfxPass$(Get-Random)",
    [Parameter()]          [string]$SiteName = "Default Web Site",
    [Parameter(Mandatory)] [string]$Hostname,
    [Parameter()]          [int]$Port = 443
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step   { param($m) Write-Host "[>] $m" -ForegroundColor Cyan }
function Write-OK     { param($m) Write-Host "[✔] $m" -ForegroundColor Green }
function Write-Warn   { param($m) Write-Host "[!] $m" -ForegroundColor Yellow }
function Write-Fail   { param($m) Write-Host "[✘] $m" -ForegroundColor Red; throw $m }
function Write-Header { param($m) Write-Host "`n━━━ $m ━━━`n" -ForegroundColor Blue }

Write-Header "Deploy TLS Certificate to IIS"

# ── Check IIS module ───────────────────────────────────────────────────────
Import-Module WebAdministration -ErrorAction Stop
Write-OK "WebAdministration module loaded"

# ── Convert PEM to PFX if needed ──────────────────────────────────────────
$pfxPath = $CertPath
if ($CertPath -match '\.pem$') {
    Write-Step "PEM format detected — converting to PFX..."
    if (-not $KeyPath) { Write-Fail "Specify -KeyPath when using PEM format" }
    if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
        Write-Fail "openssl not found in PATH. Install Git for Windows or OpenSSL."
    }

    $pfxPath = [IO.Path]::ChangeExtension($CertPath, '.pfx')
    openssl pkcs12 -export `
        -in $CertPath `
        -inkey $KeyPath `
        -out $pfxPath `
        -passout "pass:$PfxPassword"
    Write-OK "Converted to PFX: $pfxPath"
}

# ── Import into Windows Certificate Store ─────────────────────────────────
Write-Step "Importing certificate into Windows certificate store..."
Write-Step "(Store: LocalMachine\My — where IIS reads certificates)"

$securePassword = ConvertTo-SecureString -String $PfxPassword -AsPlainText -Force
$cert = Import-PfxCertificate `
    -FilePath $pfxPath `
    -CertStoreLocation "Cert:\LocalMachine\My" `
    -Password $securePassword

Write-OK "Imported certificate:"
Write-OK "  Subject    : $($cert.Subject)"
Write-OK "  Thumbprint : $($cert.Thumbprint)"
Write-OK "  Expires    : $($cert.NotAfter)"

# ── Bind to IIS ───────────────────────────────────────────────────────────
Write-Step "Configuring IIS binding for '$SiteName' → $Hostname`:$Port..."

# Remove existing binding if present (prevents duplicate binding error)
Get-WebBinding -Name $SiteName -Protocol https -Port $Port -HostHeader $Hostname `
    -ErrorAction SilentlyContinue | Remove-WebBinding -ErrorAction SilentlyContinue

# Create the HTTPS binding with SNI (Server Name Indication)
# SNI allows multiple HTTPS sites to share a single IP address
New-WebBinding -Name $SiteName `
    -Protocol https `
    -Port $Port `
    -HostHeader $Hostname `
    -SslFlags 1   # 1 = SNI required

# Assign the certificate to the binding
$binding = Get-WebBinding -Name $SiteName -Protocol https -Port $Port -HostHeader $Hostname
$binding.AddSslCertificate($cert.Thumbprint, "My")
Write-OK "Certificate bound to IIS site: $SiteName"

# ── Restart IIS site ──────────────────────────────────────────────────────
Write-Step "Restarting IIS site '$SiteName'..."
Stop-WebSite -Name $SiteName
Start-WebSite -Name $SiteName
Write-OK "IIS site restarted"

Write-Header "Complete"
Write-OK "HTTPS is now active:"
Write-OK "  URL        : https://$Hostname`:$Port"
Write-OK "  Certificate: $($cert.Subject)"
Write-OK "  Expires    : $($cert.NotAfter)"
Write-Host ""
Write-Host "Test your certificate: https://www.ssllabs.com/ssltest/analyze.html?d=$Hostname" -ForegroundColor Cyan
