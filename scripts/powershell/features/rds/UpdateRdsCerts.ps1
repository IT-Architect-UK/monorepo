# UpdateRdsCerts.ps1
# Stored in D:\Scripts\RdsCertRenew
# This script tracks the thumbprint of the RDS certificate in the WebHosting store.
# If the thumbprint has changed since the last run, it exports the new certificate to a temporary PFX,
# updates all RDS roles, and updates the state file with the new thumbprint.
# Logs each run, rotating the log daily by moving the previous day's log to the Archive directory.
# Deletes archive logs older than 5 days.
# Queries RDS configuration for Connection Broker and Certificate Common Name dynamically.
# Supports diagnostic mode: Run with -diagnostic to simulate actions without making changes.

param(
    [switch]$diagnostic
)

# Parameters
$ScriptDir = "D:\Scripts\RdsCertRenew"
$ArchiveDir = "$ScriptDir\Archive"
$StateFile = "$ScriptDir\current_thumbprint.txt"
$LogFile = "$ScriptDir\RdsCertRenew.log"
$TempPfxPath = "$ScriptDir\rds_cert_temp.pfx"
$TempPfxPassword = "TempPassword123!"  # Change to a secure password; consider using SecureString from a vault in production

# Ensure directories exist
if (-not (Test-Path $ArchiveDir)) { New-Item -Path $ArchiveDir -ItemType Directory | Out-Null }
if (-not (Test-Path $ScriptDir)) { throw "Script directory not found." }

# Delete archive logs older than 5 days
Get-ChildItem -Path $ArchiveDir -Filter "*.log" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-5) } |
    Remove-Item -Force

# Rotate log if it's a new day
if (Test-Path $LogFile) {
    $logModTime = (Get-Item $LogFile).LastWriteTime
    if ($logModTime.Date -lt (Get-Date).Date) {
        $archiveLogName = "RdsCertRenew_$(Get-Date $logModTime -Format 'yyyyMMdd').log"
        Move-Item -Path $LogFile -Destination "$ArchiveDir\$archiveLogName" -Force
    }
}

# Start logging (append if same day, new if rotated)
Start-Transcript -Path $LogFile -Append -Force
Write-Host "Script started at $(Get-Date)"
if ($diagnostic) { Write-Host "Running in diagnostic mode: No changes will be made." }

try {
    # Query current RDS certificate to derive Common Name (assuming consistent across roles)
    $CurrentRDSCert = Get-RDCertificate -Role RDPublishing  # Use RDPublishing as a representative role
    if (-not $CurrentRDSCert) {
        throw "Unable to retrieve current RDS certificate configuration."
    }
    $CertCommonName = ($CurrentRDSCert.Subject -split ',')[0] -replace 'CN=', '' -replace '\s+', ''
    Write-Host "Detected Certificate Common Name: $CertCommonName"

    # Query Connection Broker (for single-broker deployments; adjust for HA if needed)
    $ConnectionBroker = (Get-RDServer -Role RDS-CONNECTION-BROKER).Server
    if (-not $ConnectionBroker) {
        throw "Unable to detect RD Connection Broker."
    }
    Write-Host "Detected Connection Broker: $ConnectionBroker"

    # Get the latest certificate from WebHosting store matching the detected CN
    $Cert = Get-ChildItem -Path Cert:\LocalMachine\WebHosting |
            Where-Object { $_.Subject -like "*CN=$CertCommonName*" } |
            Sort-Object NotBefore -Descending |
            Select-Object -First 1

    if (-not $Cert) {
        throw "No matching certificate found in Cert:\LocalMachine\WebHosting."
    }

    $CurrentThumbprint = $Cert.Thumbprint
    Write-Host "Current certificate thumbprint: $CurrentThumbprint"

    # Read previous thumbprint from state file
    $PreviousThumbprint = if (Test-Path $StateFile) { Get-Content $StateFile -Raw } else { "" }

    if ($CurrentThumbprint -ne $PreviousThumbprint.Trim()) {
        Write-Host "Thumbprint changed. Updating RDS roles..."

        $SecurePassword = ConvertTo-SecureString -String $TempPfxPassword -Force -AsPlainText

        if (-not $diagnostic) {
            # Export to temporary PFX
            Export-PfxCertificate -Cert $Cert -FilePath $TempPfxPath -Password $SecurePassword
            Write-Host "Exported certificate to $TempPfxPath"
        } else {
            Write-Host "Diagnostic: Would export certificate to $TempPfxPath"
        }

        # Update RDS roles
        $Roles = @("RDRedirector", "RDPublishing", "RDWebAccess", "RDGateway")
        foreach ($Role in $Roles) {
            if (-not $diagnostic) {
                Set-RDCertificate -Role $Role -ImportPath $TempPfxPath -Password $SecurePassword -ConnectionBroker $ConnectionBroker -Force
                Write-Host "Updated $Role with new certificate."
            } else {
                Write-Host "Diagnostic: Would update $Role with new certificate."
            }
        }

        if (-not $diagnostic) {
            # Update state file
            $CurrentThumbprint | Out-File -FilePath $StateFile -Force
            Write-Host "Updated state file with new thumbprint."

            # Clean up temporary PFX
            Remove-Item -Path $TempPfxPath -Force
            Write-Host "Cleaned up temporary PFX file."
        } else {
            Write-Host "Diagnostic: Would update state file with new thumbprint."
            Write-Host "Diagnostic: Would clean up temporary PFX file."
        }
    } else {
        Write-Host "Thumbprint unchanged. No update needed."
    }
} catch {
    Write-Host "Error: $_"
} finally {
    Write-Host "Script ended at $(Get-Date)"
    Stop-Transcript
}