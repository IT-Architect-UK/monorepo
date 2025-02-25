# Introduction Section
<#
.SYNOPSIS
    This script audits system PAM hardening settings against desired values without modifying them.
    Settings reference: https://docs.delinea.com/online-help/secret-server/networking/distributed-engines/distributed-engine-hardening/index.htm
.DESCRIPTION
    The script collects Group Policy results using gpresult.exe, saves them in XML and HTML formats,
    and checks multiple specified hardening settings against desired values, including service states.
    It logs all actions to the screen and a log file, and generates per-computer reports. GPO settings are validated
    by searching the GPResult XML and checking the registry independently. Service settings check the service state
    and registry. Compliance is 'Compliant' if either XML or registry matches the desired value for GPOs, or if the
    service matches the desired state. RDS settings are checked via registry only due to inconsistent XML format.
    SSL/TLS protocols are consolidated under ISS.2.1.9.
    Reports include reference numbers, XML file path, line number (where applicable), and registry/service details.
.PARAMETER ServerListPath
    Optional path to a text file containing a list of server FQDNs (one per line) to audit.
.NOTES
    Author: Darren Pilkington
    Date: February 25, 2025
    No system changes are made—purely an auditing tool.
#>

# Define parameter for server list file path
Param (
    [Parameter(Mandatory = $false)]
    [string]$ServerListPath
)

# Set up variables and directories
$DateStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BaseOutputDir = "E:\TechSpecAudit"
$LogDir = "$BaseOutputDir\Logs"
$ReportDir = "$BaseOutputDir\Reports"

# Create directories if they don’t exist
foreach ($Dir in $BaseOutputDir, $LogDir, $ReportDir) {
    if (-not (Test-Path $Dir)) {
        New-Item -Path $Dir -ItemType Directory -Force | Out-Null
    }
}

# Log file setup
$LogFile = "$LogDir\AuditLog_$DateStamp.log"

# Function to write to both screen and log
function Write-Log {
    param ([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] $Message"
    Write-Host $LogMessage
    Add-Content -Path $LogFile -Value $LogMessage
}

# Define service settings
$ServiceSettings = @(
    [PSCustomObject]@{
        Reference = "ISS.1.4.1"
        SettingName = "Routing and Remote Access Service Disabled"
        Description = "Ensures the Routing and Remote Access service is disabled to prevent unauthorized network access."
        DesiredState = "Disabled"
        ServiceName = "RemoteAccess"
        RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\RemoteAccess"
        RegistryValueName = "Start"
    },
    [PSCustomObject]@{
        Reference = "ISS.1.4.11"
        SettingName = "Special Administration Console Helper Disabled"
        Description = "Allows administrators to remotely access a command prompt using Emergency Management Services."
        DesiredState = "Disabled"
        ServiceName = "sacsvr"
        RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\sacsvr"
        RegistryValueName = "Start"
    },
    [PSCustomObject]@{
        Reference = "ISS.1.4.13"
        SettingName = "Windows Error Reporting Service"
        Description = "Allows errors to be reported when programs stop working or responding."
        DesiredState = "Disabled"
        ServiceName = "WerSvc"
        RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WerSvc"
        RegistryValueName = "Start"
    }
)

# Define GPO hardening settings with XML search parameters (no namespace prefix)
$HardeningSettings = @(
    [PSCustomObject]@{
        Reference = "ISS.1.4.2"
        SettingName = "Prevent Local Guests Group from Accessing System Event Log"
        Description = "This setting prevents members of the Guests group from accessing the System event log, reducing the risk of unauthorized access to sensitive system events."
        PolicyPath = "Computer Configuration - Policies - Windows Settings - Security Settings - Event Log"
        DesiredValue = "Enabled"
        DefaultValue = "Enabled"
        RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\System"
        RegistryValueName = "RestrictGuestAccess"
        XmlNode = "EventLog"
        XmlName = "RestrictGuestAccess"
        XmlFilter = "Log='System'"
        XmlValueField = "SettingBoolean"
    },
    [PSCustomObject]@{
        Reference = "ISS.1.4.5"
        SettingName = "Audit Use of Backup and Restore Privilege"
        Description = "This setting enables auditing of the use of Backup and Restore privileges, enhancing security monitoring."
        PolicyPath = "Computer Configuration - Policies - Windows Settings - Security Settings - Local Policies - Security Options"
        DesiredValue = "Enabled"
        DefaultValue = "Disabled"
        RegistryPath = "HKLM:\System\CurrentControlSet\Control\Lsa"
        RegistryValueName = "FullPrivilegeAuditing"
        XmlNode = "SecurityOptions"
        XmlName = "Audit: Audit the use of Backup and Restore privilege"
        XmlFilter = "KeyName='MACHINE\System\CurrentControlSet\Control\Lsa\FullPrivilegeAuditing'"
        XmlValueField = "SettingNumber"
    },
    [PSCustomObject]@{
        Reference = "ISS.1.4.6"
        SettingName = "Interactive logon: Do not display last user name"
        Description = "This security setting determines whether the Windows sign-in screen will show the username of the last person who signed in."
        PolicyPath = "Computer Configuration - Policies - Windows Settings - Security Settings - Local Policies - Security Options"
        DesiredValue = "Enabled"
        DefaultValue = "Disabled"
        RegistryPath = "HKLM:\Software\Microsoft\Windows\CurrentVersion\Policies\System"
        RegistryValueName = "DontDisplayLastUserName"
        XmlNode = "SecurityOptions"
        XmlName = "Interactive logon:"
        XmlFilter = "KeyName='MACHINE\Software\Microsoft\Windows\CurrentVersion\Policies\System\DontDisplayLastUserName'"
        XmlValueField = "SettingNumber"
    },
    [PSCustomObject]@{
        Reference = "ISS.1.4.7"
        SettingName = "Microsoft network server: Attempt S4U2Self to obtain claim information"
        Description = "This setting determines whether the local file server will attempt to use Kerberos Service-For-User-To-Self (S4U2Self) functionality."
        PolicyPath = "Computer Configuration - Policies - Windows Settings - Security Settings - Local Policies - Security Options"
        DesiredValue = "Disabled"
        DefaultValue = "Disabled"
        RegistryPath = "HKLM:\System\CurrentControlSet\Services\LanManServer\Parameters"
        RegistryValueName = "enables4u2selfforclaims"
        XmlNode = "SecurityOptions"
        XmlName = "Microsoft network server: Attempt S4U2Self to obtain claim information"
        XmlFilter = "KeyName='MACHINE\System\CurrentControlSet\Services\LanManServer\Parameters\EnableS4U2SelfForClaims'"
        XmlValueField = "SettingNumber"
    },
    [PSCustomObject]@{
        Reference = "ISS.1.4.8"
        SettingName = "Recovery console: Allow automatic administrative logon"
        Description = "This security setting determines if the password for the Administrator account must be given before access to the system is granted."
        PolicyPath = "Computer Configuration - Policies - Windows Settings - Security Settings - Local Policies - Security Options"
        DesiredValue = "Disabled"
        DefaultValue = "Disabled"
        RegistryPath = "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Setup\RecoveryConsole"
        RegistryValueName = "securitylevel"
        XmlNode = "SecurityOptions"
        XmlName = "Recovery console: Allow automatic administrative logon"
        XmlFilter = "KeyName='MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Setup\RecoveryConsole\SecurityLevel'"
        XmlValueField = "SettingNumber"
    },
    [PSCustomObject]@{
        Reference = "ISS.1.4.9"
        SettingName = "Recovery console: Allow floppy copy and access to all drives and all folders"
        Description = "Enabling this security option makes the Recovery Console SET command available & allows copying files from the hard disk to a floppy disk."
        PolicyPath = "Computer Configuration - Policies - Windows Settings - Security Settings - Local Policies - Security Options"
        DesiredValue = "Disabled"
        DefaultValue = "Disabled"
        RegistryPath = "HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Setup\RecoveryConsole"
        RegistryValueName = "setcommand"
        XmlNode = "SecurityOptions"
        XmlName = "Recovery console: Allow floppy copy and access to all drives and all folders"
        XmlFilter = "KeyName='MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Setup\RecoveryConsole\SetCommand'"
        XmlValueField = "SettingNumber"
    },
    [PSCustomObject]@{
        Reference = "ISS.1.4.35"
        SettingName = "Prevent Local Guests Group from Accessing Application Event Log"
        Description = "This setting prevents members of the Guests group from accessing the Application event log, reducing the risk of unauthorized access to sensitive system events."
        PolicyPath = "Computer Configuration - Policies - Windows Settings - Security Settings - Event Log"
        DesiredValue = "Enabled"
        DefaultValue = "Enabled"
        RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Application"
        RegistryValueName = "RestrictGuestAccess"
        XmlNode = "EventLog"
        XmlName = "RestrictGuestAccess"
        XmlFilter = "Log='Application'"
        XmlValueField = "SettingBoolean"
    },
    [PSCustomObject]@{
        Reference = "ISS.1.4.36"
        SettingName = "Prevent Local Guests Group from Accessing Security Event Log"
        Description = "This setting prevents members of the Guests group from accessing the Security event log, reducing the risk of unauthorized access to sensitive system events."
        PolicyPath = "Computer Configuration - Policies - Windows Settings - Security Settings - Event Log"
        DesiredValue = "Enabled"
        DefaultValue = "Enabled"
        RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\EventLog\Security"
        RegistryValueName = "RestrictGuestAccess"
        XmlNode = "EventLog"
        XmlName = "RestrictGuestAccess"
        XmlFilter = "Log='Security'"
        XmlValueField = "SettingBoolean"
    }
)

# Define RDS settings (registry-only checks)
$RDSSettings = @(
    [PSCustomObject]@{
        Reference = "ISS.1.4.12"
        SettingName = "Do not allow local administrators to customize permissions"
        Description = "Prevents local administrators from customizing security permissions for Remote Desktop Services."
        PolicyPath = "Computer Configuration - Policies - Administrative Templates - Windows Components - Remote Desktop Services - Remote Desktop Session Host - Security"
        DesiredValue = "Enabled"
        DefaultValue = "Disabled"
        RegistryPath = "HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services"
        RegistryValueName = "fAllowUnlistedRemotePrograms"
    },
    [PSCustomObject]@{
        Reference = "ISS.1.4.17"
        SettingName = "Automatic reconnection"
        Description = "Controls whether Remote Desktop clients automatically reconnect if the connection is dropped."
        PolicyPath = "Computer Configuration - Policies - Administrative Templates - Windows Components - Remote Desktop Services - Remote Desktop Session Host - Connections"
        DesiredValue = "Disabled"
        DefaultValue = "Enabled"
        RegistryPath = "HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services"
        RegistryValueName = "fDisableAutoReconnect"
    },
    [PSCustomObject]@{
        Reference = "ISS.1.4.20"
        SettingName = "Remove Disconnect option from Shut Down dialog"
        Description = "Removes the Disconnect option from the Shut Down Windows dialog in Remote Desktop sessions."
        PolicyPath = "Computer Configuration - Policies - Administrative Templates - Windows Components - Remote Desktop Services - Remote Desktop Session Host - Connections"
        DesiredValue = "Enabled"
        DefaultValue = "Disabled"
        RegistryPath = "HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services"
        RegistryValueName = "fHideDisconnectOption"
    },
    [PSCustomObject]@{
        Reference = "ISS.1.4.30"
        SettingName = "Remove Windows Security item from Start menu"
        Description = "Removes the Windows Security item from the Start menu in Remote Desktop sessions."
        PolicyPath = "Computer Configuration - Policies - Administrative Templates - Windows Components - Remote Desktop Services - Remote Desktop Session Host - Security"
        DesiredValue = "Enabled"
        DefaultValue = "Disabled"
        RegistryPath = "HKLM:\Software\Policies\Microsoft\Windows NT\Terminal Services"
        RegistryValueName = "fHideSecurityOption"
    }
)

# Define network adapter protocol settings
$NetworkSettings = @(
    [PSCustomObject]@{
        Reference = "ISS.1.4.4"
        SettingName = "QoS Packet Scheduler Disabled"
        Description = "Ensures QoS Packet Scheduler is disabled on active Ethernet adapters for Distributed Engine servers."
        DesiredState = "Disabled"
        ProtocolName = "QoS Packet Scheduler"
        BindingName = "ms_pacer"
        AppliesToDE = $true
    },
    [PSCustomObject]@{
        Reference = "ISS.1.4.14"
        SettingName = "Client for Microsoft Network Enabled"
        Description = "Ensures Client for Microsoft Networks is enabled on active Ethernet adapters for network connectivity."
        DesiredState = "Enabled"
        ProtocolName = "Client for Microsoft Networks"
        BindingName = "ms_msclient"
    },
    [PSCustomObject]@{
        Reference = "ISS.1.4.15"
        SettingName = "File and Printer Sharing for Microsoft Network Enabled"
        Description = "Ensures File and Printer Sharing is enabled on active Ethernet adapters for resource sharing."
        DesiredState = "Enabled"
        ProtocolName = "File and Printer Sharing for Microsoft Networks"
        BindingName = "ms_server"
    },
    [PSCustomObject]@{
        Reference = "ISS.1.4.16"
        SettingName = "Internet Protocol Version 4 (TCP/IPv4) Enabled"
        Description = "Ensures IPv4 is enabled on active Ethernet adapters for network communication."
        DesiredState = "Enabled"
        ProtocolName = "Internet Protocol Version 4 (TCP/IPv4)"
        BindingName = "ms_tcpip"
    }
)

# Define filesystem permissions settings
$FilesystemSettings = @(
    [PSCustomObject]@{
        Reference = "ISS.1.4.3"
        SettingName = "System32 Config Folder Permissions"
        Description = "Ensures proper auditing permissions are set on %SystemRoot%\System32\config for the 'Everyone' principal."
        Path = "$env:SystemRoot\System32\config"
        Principal = "Everyone"
        DesiredPermissions = @(
            "Traverse Folder/Execute File",
            "List Folder/Read Data",
            "Read Attributes",
            "Read Extended Attributes"
        )
    }
)

# Define SSL/TLS protocol settings for consolidated checking under ISS.2.1.9
$SSLSettings = @(
    [PSCustomObject]@{
        Protocol = "SSLv2"
        RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 2.0\Server"
        RegistryValueName = "Enabled"
        DesiredValue = 0
        DesiredState = "Disabled"
        Description = "SSLv2 is deprecated and insecure."
    },
    [PSCustomObject]@{
        Protocol = "SSLv3"
        RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\SSL 3.0\Server"
        RegistryValueName = "Enabled"
        DesiredValue = 0
        DesiredState = "Disabled"
        Description = "SSLv3 is deprecated and insecure."
    },
    [PSCustomObject]@{
        Protocol = "TLSv1.0"
        RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.0\Server"
        RegistryValueName = "Enabled"
        DesiredValue = 0
        DesiredState = "Disabled"
        Description = "TLSv1.0 is considered weak and should be disabled."
    },
    [PSCustomObject]@{
        Protocol = "TLSv1.1"
        RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.1\Server"
        RegistryValueName = "Enabled"
        DesiredValue = 0
        DesiredState = "Disabled"
        Description = "TLSv1.1 may be disabled depending on security requirements."
    },
    [PSCustomObject]@{
        Protocol = "TLSv1.2"
        RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server"
        RegistryValueName = "Enabled"
        DesiredValue = -1
        DesiredState = "Enabled"
        Description = "TLSv1.2 is secure and should be enabled."
    },
    [PSCustomObject]@{
        Protocol = "TLSv1.3"
        RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.3\Server"
        RegistryValueName = "Enabled"
        DesiredValue = -1
        DesiredState = "Enabled"
        Description = "TLSv1.3 is the most secure and should be enabled if supported."
    }
)

# Credential Prompt
$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$DomainUsername = $CurrentUser.Name

Write-Host "Specify credentials for running the script."
Write-Host "Current user: $DomainUsername"
Write-Host "Press Enter at the password prompt to use current credentials, or enter a password for explicit credentials."
$Username = Read-Host "Enter username (default: $DomainUsername)"
$Password = Read-Host "Enter password (leave blank for current credentials)" -AsSecureString

if ([string]::IsNullOrEmpty($Username)) { $Username = $DomainUsername }

if ([string]::IsNullOrEmpty([PSCredential]::new("dummy", $Password).GetNetworkCredential().Password)) {
    Write-Log "Using current logged-on credentials for - $Username"
    $Credential = $null
} else {
    try {
        $Credential = New-Object System.Management.Automation.PSCredential ($Username, $Password)
        Write-Log "Using explicitly specified credentials - $Username"
    } catch {
        Write-Log "Failed to create credential object for $Username - $_"
        Write-Host "Error: Invalid credentials provided. Exiting script."
        exit 1
    }
}

# Determine Computer List
if ($ServerListPath) {
    if (Test-Path $ServerListPath) {
        $ComputerList = Get-Content -Path $ServerListPath | Where-Object { $_ -match '\S' }
        if ($ComputerList.Count -eq 0) {
            Write-Log "Server list file '$ServerListPath' is empty. Defaulting to local computer - $env:COMPUTERNAME"
            $ComputerList = @($env:COMPUTERNAME)
        } else {
            Write-Log "Loaded computer list from file - $ServerListPath"
        }
    } else {
        Write-Log "Server list path '$ServerListPath' does not exist. Defaulting to local computer - $env:COMPUTERNAME"
        $ComputerList = @($env:COMPUTERNAME)
    }
} else {
    Write-Host "Please specify the computers to audit."
    Write-Host "Enter 'local' for the local machine (default), or provide a text file path with computer names (one per line)"
    $ComputerInput = Read-Host "Computer selection (press Enter for 'local')"
    if ([string]::IsNullOrEmpty($ComputerInput) -or $ComputerInput -eq "local") {
        $ComputerList = @($env:COMPUTERNAME)
        Write-Log "Selected local computer - $env:COMPUTERNAME"
    } elseif (Test-Path $ComputerInput) {
        $ComputerList = Get-Content -Path $ComputerInput | Where-Object { $_ -match '\S' }
        if ($ComputerList.Count -eq 0) {
            Write-Log "Computer list file '$ComputerInput' is empty. Defaulting to local - $env:COMPUTERNAME"
            $ComputerList = @($env:COMPUTERNAME)
        } else {
            Write-Log "Loaded computer list from file - $ComputerInput"
        }
    } else {
        Write-Log "Invalid input '$ComputerInput'. Defaulting to local computer - $env:COMPUTERNAME"
        $ComputerList = @($env:COMPUTERNAME)
    }
}

# Function to Test Computer Access
function Test-ComputerAccess {
    param (
        [string]$ComputerName,
        [PSCredential]$Cred
    )
    Write-Log "Testing access for $ComputerName"
    if ($ComputerName -eq $env:COMPUTERNAME) {
        try {
            $null = Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services" -ErrorAction Stop
            Write-Log "Local registry access confirmed for $ComputerName"
            return $true
        } catch {
            Write-Log "Local registry access denied for $ComputerName - $_"
            return $false
        }
    } else {
        try {
            $SessionArgs = @{ ComputerName = $ComputerName; ErrorAction = 'Stop' }
            if ($Cred) { $SessionArgs['Credential'] = $Cred }
            $Session = New-PSSession @SessionArgs
            Remove-PSSession $Session
            Write-Log "PSRemoting and registry access confirmed for $ComputerName"
            return $true
        } catch {
            Write-Log "Failed to access $ComputerName - PSRemoting or permissions issue - $_"
            return $false
        }
    }
}

# Process Each Computer
foreach ($Computer in $ComputerList) {
    Write-Log "Starting audit for computer - $Computer"
    if (-not (Test-ComputerAccess -ComputerName $Computer -Cred $Credential)) {
        Write-Log "Skipping $Computer due to access failure"
        continue
    }

    $ComputerReportDir = "$ReportDir\$Computer"
    if (-not (Test-Path $ComputerReportDir)) {
        New-Item -Path $ComputerReportDir -ItemType Directory -Force | Out-Null
    }

    $GpXmlFile = "$ComputerReportDir\GPResult_$DateStamp.xml"
    $GpHtmlFile = "$ComputerReportDir\GPResult_$DateStamp.html"

    Write-Log "Collecting GPResult for $Computer"
    try {
        if ($Computer -eq $env:COMPUTERNAME) {
            gpresult /SCOPE COMPUTER /X $GpXmlFile /F | Out-Null
            gpresult /SCOPE COMPUTER /H $GpHtmlFile /F | Out-Null
        } else {
            $GpArgs = @("/S", $Computer, "/SCOPE", "COMPUTER", "/X", $GpXmlFile, "/F")
            if ($Credential) {
                $GpArgs += @("/U", $Credential.UserName, "/P", $Credential.GetNetworkCredential().Password)
            }
            Start-Process "gpresult" -ArgumentList $GpArgs -NoNewWindow -Wait -RedirectStandardOutput "$env:TEMP\gpresult.out" -ErrorAction Stop
            Remove-Item "$env:TEMP\gpresult.out" -ErrorAction SilentlyContinue
            $GpArgs[4] = "/H"; $GpArgs[5] = $GpHtmlFile
            Start-Process "gpresult" -ArgumentList $GpArgs -NoNewWindow -Wait -RedirectStandardOutput "$env:TEMP\gpresult.out" -ErrorAction Stop
            Remove-Item "$env:TEMP\gpresult.out" -ErrorAction SilentlyContinue
        }
        if (Test-Path $GpXmlFile) {
            Write-Log "GPResult collected - XML at $GpXmlFile, HTML at $GpHtmlFile"
        } else {
            throw "GPResult XML file not created"
        }
    } catch {
        Write-Log "Failed to collect GPResult for $Computer - $_"
        continue
    }

    [xml]$GpXml = Get-Content $GpXmlFile
    $GpXmlLines = Get-Content $GpXmlFile
    $ReportFile = "$ComputerReportDir\HardeningReport_$DateStamp.txt"
    "System Hardening Audit Report - $Computer - $DateStamp" | Out-File $ReportFile
    "" | Out-File $ReportFile -Append

    # Service Settings
    "=== Service Settings ===" | Out-File $ReportFile -Append
    foreach ($Setting in $ServiceSettings) {
        Write-Log "Checking $($Setting.SettingName)"
        "Reference - $($Setting.Reference)" | Out-File $ReportFile -Append
        "Setting - $($Setting.SettingName)" | Out-File $ReportFile -Append
        "Description - $($Setting.Description)" | Out-File $ReportFile -Append
        "Desired State - $($Setting.DesiredState)" | Out-File $ReportFile -Append

        $ServiceState = "Not found"
        try {
            if ($Computer -eq $env:COMPUTERNAME) {
                $Service = Get-Service -Name $Setting.ServiceName -ErrorAction Stop
                $ServiceState = $Service.StartType
            } else {
                $InvokeArgs = @{ ComputerName = $Computer; ScriptBlock = { param($Name) Get-Service -Name $Name -ErrorAction Stop }; ArgumentList = $Setting.ServiceName; ErrorAction = 'Stop' }
                if ($Credential) { $InvokeArgs['Credential'] = $Credential }
                $Service = Invoke-Command @InvokeArgs
                $ServiceState = $Service.StartType
            }
            "Service State - $ServiceState" | Out-File $ReportFile -Append
        } catch {
            Write-Log "Error checking service state for $($Setting.SettingName) - $_"
            "Service State - Not found (check failed - $_)" | Out-File $ReportFile -Append
        }

        $RegServiceValue = "Not set"
        $RegRawValue = $null
        try {
            $RegValueObj = if ($Computer -eq $env:COMPUTERNAME) {
                if (Test-Path $Setting.RegistryPath) { Get-ItemProperty -Path $Setting.RegistryPath -ErrorAction Stop }
            } else {
                $InvokeArgs = @{ ComputerName = $Computer; ScriptBlock = { param($Path) if (Test-Path $Path) { Get-ItemProperty -Path $Path -ErrorAction Stop } }; ArgumentList = $Setting.RegistryPath; ErrorAction = 'Stop' }
                if ($Credential) { $InvokeArgs['Credential'] = $Credential }
                Invoke-Command @InvokeArgs
            }
            if ($RegValueObj -and $RegValueObj.PSObject.Properties.Name -contains $Setting.RegistryValueName) {
                $RegRawValue = $RegValueObj.$($Setting.RegistryValueName)
                $RegServiceValue = switch ($RegRawValue) { 2 {"Automatic"} 3 {"Manual"} 4 {"Disabled"} default {"Unknown ($RegRawValue)"} }
            }
            "Registry Key - $($Setting.RegistryPath)" | Out-File $ReportFile -Append
            "Registry Value Name - $($Setting.RegistryValueName)" | Out-File $ReportFile -Append
            "Registry Value - $RegServiceValue (Raw: $RegRawValue)" | Out-File $ReportFile -Append
        } catch {
            Write-Log "Error checking registry for $($Setting.SettingName) - $_"
            "Registry Key - $($Setting.RegistryPath)" | Out-File $ReportFile -Append
            "Registry Value Name - $($Setting.RegistryValueName)" | Out-File $ReportFile -Append
            "Registry Value - Not set (check failed - $_)" | Out-File $ReportFile -Append
        }

        $Compliance = if ($ServiceState -eq $Setting.DesiredState -or $RegServiceValue -eq $Setting.DesiredState) { "Compliant" } else { "Non-Compliant" }
        "Compliance - $Compliance" | Out-File $ReportFile -Append
        "" | Out-File $ReportFile -Append
    }

    # GPO Settings
    "=== GPO Settings ===" | Out-File $ReportFile -Append
    foreach ($Setting in $HardeningSettings) {
        Write-Log "Checking $($Setting.SettingName)"
        "Reference - $($Setting.Reference)" | Out-File $ReportFile -Append
        "Setting - $($Setting.SettingName)" | Out-File $ReportFile -Append
        "Description - $($Setting.Description)" | Out-File $ReportFile -Append
        "Policy Path - $($Setting.PolicyPath)" | Out-File $ReportFile -Append
        "Desired Value - $($Setting.DesiredValue)" | Out-File $ReportFile -Append
        "Default Value - $($Setting.DefaultValue)" | Out-File $ReportFile -Append

        $XmlValue = "Not set"
        try {
            $XPath = "//*[local-name()='$($Setting.XmlNode)']"
            if ($Setting.XmlFilter) { $XPath += "[.//*[local-name()='$($Setting.XmlFilter.Split('=')[0])' and .='$($Setting.XmlFilter.Split('=')[1].Trim("'"))']]" }
            $XPath += "[contains(.//*[local-name()='Name'],'$($Setting.XmlName)') or contains(.//*[local-name()='KeyName'],'$($Setting.XmlName)')]"
            $Nodes = $GpXml.SelectNodes($XPath)
            foreach ($Node in $Nodes) {
                if ($Node.LocalName -eq $Setting.XmlNode) {
                    $ValueNode = $Node.SelectSingleNode("*[local-name()='$($Setting.XmlValueField)']")
                    if (-not $ValueNode) {
                        $ValueNode = $Node.SelectSingleNode(".//*[local-name()='Display']/*[local-name()='DisplayBoolean']")
                    }
                    if ($ValueNode) {
                        $XmlValue = if ($Setting.XmlValueField -eq "SettingNumber") { if ($ValueNode.InnerText -eq '1') {"Enabled"} else {"Disabled"} } else { if ($ValueNode.InnerText -eq 'true') {"Enabled"} else {"Disabled"} }
                        $LineNumber = if ($Setting.XmlFilter) {
                            ($GpXmlLines | Select-String "<[^>]*KeyName>$([regex]::Escape($Setting.XmlFilter.Split('=')[1].Trim("'")))</[^>]*>" | Select-Object -First 1).LineNumber
                        } else {
                            ($GpXmlLines | Select-String "<[^>]*KeyName>$([regex]::Escape($Setting.XmlName))</[^>]*>|<[^>]*Name>$([regex]::Escape($Setting.XmlName))</[^>]*>" | Select-Object -First 1).LineNumber
                        }
                        "GPResult Value - $XmlValue (Found in $GpXmlFile at line $LineNumber)" | Out-File $ReportFile -Append
                        break
                    }
                }
            }
            if ($XmlValue -eq "Not set") { "GPResult Value - Not set" | Out-File $ReportFile -Append }
        } catch {
            Write-Log "Error searching XML for $($Setting.SettingName) - $_"
            "GPResult Value - Not set (search error - $_)" | Out-File $ReportFile -Append
        }

        $RegValue = "Not set"
        $RegRawValue = $null
        try {
            $RegValueObj = if ($Computer -eq $env:COMPUTERNAME) {
                if (Test-Path $Setting.RegistryPath) { Get-ItemProperty -Path $Setting.RegistryPath -Name $Setting.RegistryValueName -ErrorAction SilentlyContinue }
            } else {
                $InvokeArgs = @{ ComputerName = $Computer; ScriptBlock = { param($Path, $Name) if (Test-Path $Path) { Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue } }; ArgumentList = @($Setting.RegistryPath, $Setting.RegistryValueName); ErrorAction = 'Stop' }
                if ($Credential) { $InvokeArgs['Credential'] = $Credential }
                Invoke-Command @InvokeArgs
            }
            if ($RegValueObj -and $RegValueObj.PSObject.Properties.Name -contains $Setting.RegistryValueName) {
                $RegRawValue = $RegValueObj.$($Setting.RegistryValueName)
                $RegValue = if ($Setting.RegistryValueName -eq "FullPrivilegeAuditing") {
                    if ($RegRawValue -eq 1 -or ($RegRawValue -is [byte[]] -and $RegRawValue[0] -eq 1)) {"Enabled"} else {"Disabled"}
                } else {
                    if ($RegRawValue -eq 1) {"Enabled"} else {"Disabled"}
                }
            }
            "Registry Key - $($Setting.RegistryPath)" | Out-File $ReportFile -Append
            "Registry Value Name - $($Setting.RegistryValueName)" | Out-File $ReportFile -Append
            "Registry Value - $RegValue (Raw: $(if ($RegRawValue -is [byte[]]) { '0x' + ([BitConverter]::ToString($RegRawValue) -replace '-','') } else { $RegRawValue }))" | Out-File $ReportFile -Append
        } catch {
            Write-Log "Error checking registry for $($Setting.SettingName) - $_"
            "Registry Key - $($Setting.RegistryPath)" | Out-File $ReportFile -Append
            "Registry Value Name - $($Setting.RegistryValueName)" | Out-File $ReportFile -Append
            "Registry Value - Not set (check failed - $_)" | Out-File $ReportFile -Append
        }

        $ComplianceValue = if ($XmlValue -eq "Enabled" -or $RegValue -eq "Enabled") {"Enabled"} elseif ($XmlValue -eq "Not set" -and $RegValue -eq "Not set") {$Setting.DefaultValue} else {"Disabled"}
        "Compliance - $(if ($ComplianceValue -eq $Setting.DesiredValue) {'Compliant'} else {'Non-Compliant'})" | Out-File $ReportFile -Append
        "" | Out-File $ReportFile -Append
    }

    # RDS Settings
    "=== RDS Settings ===" | Out-File $ReportFile -Append
    foreach ($Setting in $RDSSettings) {
        Write-Log "Checking $($Setting.SettingName)"
        "Reference - $($Setting.Reference)" | Out-File $ReportFile -Append
        "Setting - $($Setting.SettingName)" | Out-File $ReportFile -Append
        "Description - $($Setting.Description)" | Out-File $ReportFile -Append
        "Policy Path - $($Setting.PolicyPath)" | Out-File $ReportFile -Append
        "Desired Value - $($Setting.DesiredValue)" | Out-File $ReportFile -Append
        "Default Value - $($Setting.DefaultValue)" | Out-File $ReportFile -Append

        $RegValue = "Not set"
        $RegRawValue = $null
        try {
            $RegValueObj = if ($Computer -eq $env:COMPUTERNAME) {
                if (Test-Path $Setting.RegistryPath) { Get-ItemProperty -Path $Setting.RegistryPath -Name $Setting.RegistryValueName -ErrorAction SilentlyContinue }
            } else {
                $InvokeArgs = @{ ComputerName = $Computer; ScriptBlock = { param($Path, $Name) if (Test-Path $Path) { Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue } }; ArgumentList = @($Setting.RegistryPath, $Setting.RegistryValueName); ErrorAction = 'Stop' }
                if ($Credential) { $InvokeArgs['Credential'] = $Credential }
                Invoke-Command @InvokeArgs
            }
            if ($RegValueObj -and $RegValueObj.PSObject.Properties.Name -contains $Setting.RegistryValueName) {
                $RegRawValue = $RegValueObj.$($Setting.RegistryValueName)
                $RegValue = if ($Setting.RegistryValueName -eq "fDisableAutoReconnect") { if ($RegRawValue -eq 1) {"Disabled"} else {"Enabled"} } else { if ($RegRawValue -eq 1) {"Enabled"} else {"Disabled"} }
            }
            "Registry Key - $($Setting.RegistryPath)" | Out-File $ReportFile -Append
            "Registry Value Name - $($Setting.RegistryValueName)" | Out-File $ReportFile -Append
            "Registry Value - $RegValue (Raw: $RegRawValue)" | Out-File $ReportFile -Append
        } catch {
            Write-Log "Error checking registry for $($Setting.SettingName) - $_"
            "Registry Key - $($Setting.RegistryPath)" | Out-File $ReportFile -Append
            "Registry Value Name - $($Setting.RegistryValueName)" | Out-File $ReportFile -Append
            "Registry Value - Not set (check failed - $_)" | Out-File $ReportFile -Append
        }

        $ComplianceValue = if ($RegValue -eq "Not set") { $Setting.DefaultValue } else { $RegValue }
        "Compliance - $(if ($ComplianceValue -eq $Setting.DesiredValue) {'Compliant'} else {'Non-Compliant'})" | Out-File $ReportFile -Append
        "" | Out-File $ReportFile -Append
    }

    # Network Adapter Settings
    "=== Network Adapter Settings ===" | Out-File $ReportFile -Append
    Write-Log "Checking network adapter configurations for $Computer"
    try {
        $ActiveAdapters = if ($Computer -eq $env:COMPUTERNAME) {
            Get-NetAdapter -Physical | Where-Object { $_.MediaType -eq "802.3" -and $_.Status -eq "Up" }
        } else {
            $InvokeArgs = @{ ComputerName = $Computer; ScriptBlock = { Get-NetAdapter -Physical | Where-Object { $_.MediaType -eq "802.3" -and $_.Status -eq "Up" } }; ErrorAction = 'Stop' }
            if ($Credential) { $InvokeArgs['Credential'] = $Credential }
            Invoke-Command @InvokeArgs
        }

        if ($ActiveAdapters.Count -eq 0) {
            Write-Log "No active Ethernet adapters found on $Computer"
            "No active Ethernet adapters detected" | Out-File $ReportFile -Append
            "" | Out-File $ReportFile -Append
        } else {
            foreach ($Adapter in $ActiveAdapters) {
                "Adapter - $($Adapter.Name) ($($Adapter.InterfaceDescription))" | Out-File $ReportFile -Append
                $IsDEServer = $Computer -match "DE"
                $ApplicableSettings = if ($IsDEServer) { $NetworkSettings } else { $NetworkSettings | Where-Object { -not $_.AppliesToDE } }

                foreach ($Setting in $ApplicableSettings) {
                    Write-Log "Checking $($Setting.SettingName) for adapter $($Adapter.Name)"
                    "Reference - $($Setting.Reference)" | Out-File $ReportFile -Append
                    "Setting - $($Setting.SettingName)" | Out-File $ReportFile -Append
                    "Description - $($Setting.Description)" | Out-File $ReportFile -Append
                    "Desired State - $($Setting.DesiredState)" | Out-File $ReportFile -Append

                    $ProtocolState = "Not found"
                    try {
                        $Binding = if ($Computer -eq $env:COMPUTERNAME) {
                            Get-NetAdapterBinding -Name $Adapter.Name -DisplayName $Setting.ProtocolName -ErrorAction Stop
                        } else {
                            $InvokeArgs = @{ ComputerName = $Computer; ScriptBlock = { param($Name, $DisplayName) Get-NetAdapterBinding -Name $Name -DisplayName $DisplayName -ErrorAction Stop }; ArgumentList = @($Adapter.Name, $Setting.ProtocolName); ErrorAction = 'Stop' }
                            if ($Credential) { $InvokeArgs['Credential'] = $Credential }
                            Invoke-Command @InvokeArgs
                        }
                        $ProtocolState = if ($Binding.Enabled) {"Enabled"} else {"Disabled"}
                        "Protocol State - $ProtocolState" | Out-File $ReportFile -Append
                    } catch {
                        Write-Log "Error checking $($Setting.SettingName) for $($Adapter.Name) - $_"
                        "Protocol State - Not found (check failed - $_)" | Out-File $ReportFile -Append
                    }

                    $Compliance = if ($ProtocolState -eq $Setting.DesiredState) {"Compliant"} else {"Non-Compliant"}
                    "Compliance - $Compliance" | Out-File $ReportFile -Append
                    "" | Out-File $ReportFile -Append
                }
            }
        }
    } catch {
        Write-Log "Failed to check network adapter configurations for $Computer - $_"
        "Error checking network adapter configurations - $_" | Out-File $ReportFile -Append
        "" | Out-File $ReportFile -Append
    }

    # Filesystem Permissions Settings
    "=== Filesystem Permissions Settings ===" | Out-File $ReportFile -Append
    Write-Log "Checking filesystem auditing permissions for $Computer"
    foreach ($Setting in $FilesystemSettings) {
        Write-Log "Checking $($Setting.SettingName)"
        "Reference - $($Setting.Reference)" | Out-File $ReportFile -Append
        "Setting - $($Setting.SettingName)" | Out-File $ReportFile -Append
        "Description - $($Setting.Description)" | Out-File $ReportFile -Append
        "Path - $($Setting.Path)" | Out-File $ReportFile -Append
        "Principal - $($Setting.Principal)" | Out-File $ReportFile -Append
        "Desired Permissions - $($Setting.DesiredPermissions -join ', ')" | Out-File $ReportFile -Append

        try {
            $Acl = if ($Computer -eq $env:COMPUTERNAME) {
                Get-Acl -Path $Setting.Path -Audit -ErrorAction Stop
            } else {
                $InvokeArgs = @{ ComputerName = $Computer; ScriptBlock = { param($Path) Get-Acl -Path $Path -Audit -ErrorAction Stop }; ArgumentList = $Setting.Path; ErrorAction = 'Stop' }
                if ($Credential) { $InvokeArgs['Credential'] = $Credential }
                Invoke-Command @InvokeArgs
            }

            $ActualPermissions = @()
            $AuditRules = $Acl.Audit | Where-Object { $_.IdentityReference -eq $Setting.Principal }
            if ($AuditRules) {
                foreach ($Rule in $AuditRules) {
                    if ($Rule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ExecuteFile) { $ActualPermissions += "Traverse Folder/Execute File" }
                    if ($Rule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ReadData) { $ActualPermissions += "List Folder/Read Data" }
                    if ($Rule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ReadAttributes) { $ActualPermissions += "Read Attributes" }
                    if ($Rule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ReadExtendedAttributes) { $ActualPermissions += "Read Extended Attributes" }
                }
                $ActualPermissions = $ActualPermissions | Sort-Object -Unique
            }

            if ($ActualPermissions.Count -eq 0) {
                "Actual Permissions - None found" | Out-File $ReportFile -Append
            } else {
                "Actual Permissions - $($ActualPermissions -join ', ')" | Out-File $ReportFile -Append
            }

            $MissingPermissions = $Setting.DesiredPermissions | Where-Object { $_ -notin $ActualPermissions }
            $Compliance = if ($MissingPermissions.Count -eq 0 -and $ActualPermissions.Count -ge $Setting.DesiredPermissions.Count) {"Compliant"} else {"Non-Compliant"}
            "Compliance - $Compliance" | Out-File $ReportFile -Append
            "" | Out-File $ReportFile -Append
        } catch {
            Write-Log "Error checking filesystem permissions for $($Setting.SettingName) - $_"
            "Actual Permissions - Check failed ($_)" | Out-File $ReportFile -Append
            "Compliance - Non-Compliant (check failed)" | Out-File $ReportFile -Append
            "" | Out-File $ReportFile -Append
        }
    }

    # SSL/TLS Protocol Settings (Consolidated under ISS.2.1.9)
    "=== SSL/TLS Protocol Settings ===" | Out-File $ReportFile -Append
    Write-Log "Checking SSL/TLS protocol settings for $Computer"
    "Reference - ISS.2.1.9" | Out-File $ReportFile -Append
    "Setting - Secure SSL/TLS Protocol Configuration" | Out-File $ReportFile -Append
    "Description - Ensures secure communication protocols by enabling only modern TLS versions (TLSv1.2, TLSv1.3) and disabling deprecated protocols (SSLv2, SSLv3, TLSv1.0, TLSv1.1)." | Out-File $ReportFile -Append

    $SSLResults = @{}
    $IsCompliant = $true
    foreach ($Setting in $SSLSettings) {
        Write-Log "Checking $($Setting.Protocol)"
        $RegValue = "Not set"
        $RegRawValue = $null
        try {
            $RegValueObj = if ($Computer -eq $env:COMPUTERNAME) {
                if (Test-Path $Setting.RegistryPath) { Get-ItemProperty -Path $Setting.RegistryPath -Name $Setting.RegistryValueName -ErrorAction SilentlyContinue }
            } else {
                $InvokeArgs = @{ ComputerName = $Computer; ScriptBlock = { param($Path, $Name) if (Test-Path $Path) { Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue } }; ArgumentList = @($Setting.RegistryPath, $Setting.RegistryValueName); ErrorAction = 'Stop' }
                if ($Credential) { $InvokeArgs['Credential'] = $Credential }
                Invoke-Command @InvokeArgs
            }
            if ($RegValueObj -and $RegValueObj.PSObject.Properties.Name -contains $Setting.RegistryValueName) {
                $RegRawValue = $RegValueObj.$($Setting.RegistryValueName)
                $RegValue = if ($RegRawValue -eq 0) {"Disabled"} elseif ($RegRawValue -eq 0xffffffff -or $RegRawValue -eq -1) {"Enabled"} else {"Unknown ($RegRawValue)"}
                $SSLResults[$Setting.Protocol] = "$RegValue (Raw: $RegRawValue)"
            } else {
                $SSLResults[$Setting.Protocol] = "Not set"
                if ($Setting.Protocol -in @("TLSv1.2", "TLSv1.3")) { $RegValue = "Enabled" }  # Assume enabled if not set for modern TLS
            }
        } catch {
            Write-Log "Error checking registry for $($Setting.Protocol) - $_"
            $SSLResults[$Setting.Protocol] = "Not set (check failed - $_)"
        }

        $ActualState = if ($RegValue -eq "Not set" -and $Setting.Protocol -in @("TLSv1.2", "TLSv1.3")) { "Enabled" } else { $RegValue }
        if ($ActualState -ne $Setting.DesiredState) { $IsCompliant = $false }
    }

    "Desired States - SSLv2: Disabled, SSLv3: Disabled, TLSv1.0: Disabled, TLSv1.1: Disabled, TLSv1.2: Enabled, TLSv1.3: Enabled" | Out-File $ReportFile -Append
    "Current States:" | Out-File $ReportFile -Append
    foreach ($Protocol in $SSLResults.Keys) {
        "  $Protocol - $($SSLResults[$Protocol])" | Out-File $ReportFile -Append
    }
    "Compliance - $(if ($IsCompliant) {'Compliant'} else {'Non-Compliant'})" | Out-File $ReportFile -Append
    "" | Out-File $ReportFile -Append

    Write-Log "Completed audit for $Computer. Report saved to $ReportFile"
}

Write-Log "Script execution completed"