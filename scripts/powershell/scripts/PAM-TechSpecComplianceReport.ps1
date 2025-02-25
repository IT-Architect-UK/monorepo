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
    service matches the desired state. Reports include reference numbers, XML file path, line number, and registry/service details.
.NOTES
    Author: Darren Pilkington
    Date: February 25, 2025
    No system changes are made—purely an auditing tool.
#>

# Set up variables and directories
$DateStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BaseOutputDir = "D:\TechSpecAudit"
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
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH-mm-ss"
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
        XmlName = "Interactive logon:"  # Simplified base string for wildcard matching
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

# Define network adapter protocol settings
$NetworkSettings = @(
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
    },
    [PSCustomObject]@{
        Reference = "ISS.1.4.4"
        SettingName = "QoS Packet Scheduler Disabled"
        Description = "Ensures QoS Packet Scheduler is disabled on active Ethernet adapters for Distributed Engine servers."
        DesiredState = "Disabled"
        ProtocolName = "QoS Packet Scheduler"
        BindingName = "ms_pacer"
        AppliesToDE = $true  # Flag to indicate this check only applies to Distributed Engine servers
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

# Text-based credential prompt with default to current user
Write-Host "Specify credentials for running the script (press Enter at both prompts to use current user credentials - $env:USERNAME)"
$Username = Read-Host "Enter username (leave blank for current user)"
$Password = Read-Host "Enter password (leave blank for current user)" -AsSecureString

if ([string]::IsNullOrEmpty($Username) -and -not $Password) {
    Write-Log "Using current user credentials - $env:USERNAME"
    $Credential = $null  # Null means use current user context
} else {
    if ([string]::IsNullOrEmpty($Username)) { $Username = $env:USERNAME }
    $Credential = New-Object System.Management.Automation.PSCredential ($Username, $Password)
    Write-Log "Using specified credentials - $Username"
}

# Prompt user for computer selection
Write-Host "Please specify the computers to audit."
Write-Host "Enter 'local' for the local machine (default), or provide the path to a text file with computer names (one per line)"
$ComputerInput = Read-Host "Computer selection (press Enter for 'local')"

if ([string]::IsNullOrEmpty($ComputerInput)) {
    $ComputerList = @($env:COMPUTERNAME)
    Write-Log "Defaulting to local computer - $env:COMPUTERNAME"
} elseif ($ComputerInput -eq "local") {
    $ComputerList = @($env:COMPUTERNAME)
    Write-Log "Selected local computer - $env:COMPUTERNAME"
} elseif (Test-Path $ComputerInput) {
    $ComputerList = Get-Content -Path $ComputerInput
    Write-Log "Loaded computer list from file - $ComputerInput"
} else {
    Write-Log "Invalid input. Defaulting to local computer - $env:COMPUTERNAME"
    $ComputerList = @($env:COMPUTERNAME)
}

# Function to check PSRemoting and permissions
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

# Process each computer
foreach ($Computer in $ComputerList) {
    Write-Log "Starting audit for computer - $Computer"

    # Check PSRemoting and permissions
    if (-not (Test-ComputerAccess -ComputerName $Computer -Cred $Credential)) {
        Write-Log "Skipping $Computer due to access failure"
        continue
    }

    # Create computer-specific report folder
    $ComputerReportDir = "$ReportDir\$Computer"
    if (-not (Test-Path $ComputerReportDir)) {
        New-Item -Path $ComputerReportDir -ItemType Directory -Force | Out-Null
    }

    # Run GPResult and save output
    $GpXmlFile = "$ComputerReportDir\GPResult_$DateStamp.xml"
    $GpHtmlFile = "$ComputerReportDir\GPResult_$DateStamp.html"

    Write-Log "Collecting GPResult for $Computer"
    try {
        if ($Computer -eq $env:COMPUTERNAME) {
            gpresult /SCOPE COMPUTER /X $GpXmlFile /F | Out-Null
            gpresult /SCOPE COMPUTER /H $GpHtmlFile /F | Out-Null
        } else {
            $GpArgs = "/S $Computer /SCOPE COMPUTER"
            if ($Credential) {
                $GpArgs += " /U $($Credential.UserName) /P $($Credential.GetNetworkCredential().Password)"
            }
            Invoke-Expression "gpresult $GpArgs /X $GpXmlFile /F" | Out-Null
            Invoke-Expression "gpresult $GpArgs /H $GpHtmlFile /F" | Out-Null
        }
        if (Test-Path $GpXmlFile) {
            Write-Log "GPResult collected - XML at $GpXmlFile, HTML at $GpHtmlFile"
        } else {
            throw "GPResult file not created"
        }
    } catch {
        Write-Log "Failed to collect GPResult for $Computer - $_"
        continue
    }

    # Load GPResult XML
    [xml]$GpXml = Get-Content $GpXmlFile
    $GpXmlLines = Get-Content $GpXmlFile  # Load as lines for line number lookup

    # Report file setup
    $ReportFile = "$ComputerReportDir\HardeningReport_$DateStamp.txt"
    "System Hardening Audit Report - $Computer - $DateStamp" | Out-File $ReportFile
    "" | Out-File $ReportFile -Append

    # Separator for service settings
    "=== Service Settings ===" | Out-File $ReportFile -Append

    # Process service settings
    foreach ($ServiceSetting in $ServiceSettings) {
        Write-Log "Checking service setting - $($ServiceSetting.SettingName)"
        "Reference - $($ServiceSetting.Reference)" | Out-File $ReportFile -Append
        "Setting - $($ServiceSetting.SettingName)" | Out-File $ReportFile -Append
        "Description - $($ServiceSetting.Description)" | Out-File $ReportFile -Append
        "Desired State - $($ServiceSetting.DesiredState)" | Out-File $ReportFile -Append

        # Check service state
        $ServiceState = "Not found"
        try {
            if ($Computer -eq $env:COMPUTERNAME) {
                $Service = Get-Service -Name $ServiceSetting.ServiceName -ErrorAction Stop
                $ServiceState = $Service.StartType
                "Service State - $ServiceState" | Out-File $ReportFile -Append
            } else {
                $InvokeArgs = @{ ComputerName = $Computer; ScriptBlock = {
                    param($ServiceName)
                    Get-Service -Name $ServiceName -ErrorAction Stop
                }; ArgumentList = @($ServiceSetting.ServiceName); ErrorAction = 'Stop' }
                if ($Credential) { $InvokeArgs['Credential'] = $Credential }
                $Service = Invoke-Command @InvokeArgs
                $ServiceState = $Service.StartType
                "Service State - $ServiceState" | Out-File $ReportFile -Append
            }
        } catch {
            Write-Log "Error checking service state for $($ServiceSetting.SettingName) - $_"
            "Service State - Not found (check failed - $_)" | Out-File $ReportFile -Append
        }

        # Check registry for service startup type
        $RegServiceValue = "Not set"
        try {
            if ($Computer -eq $env:COMPUTERNAME) {
                if (Test-Path $ServiceSetting.RegistryPath) {
                    $RegValueObj = Get-ItemProperty -Path $ServiceSetting.RegistryPath -ErrorAction Stop
                    if ($RegValueObj -and $RegValueObj.PSObject.Properties.Name -contains $ServiceSetting.RegistryValueName) {
                        $RegRawValue = $RegValueObj.$($ServiceSetting.RegistryValueName)
                        Write-Log "Raw registry value for $($ServiceSetting.SettingName) at $($ServiceSetting.RegistryPath)\$($ServiceSetting.RegistryValueName): $RegRawValue"
                        $RegServiceValue = switch ($RegRawValue) {
                            2 { "Automatic" }
                            3 { "Manual" }
                            4 { "Disabled" }
                            default { "Unknown ($RegRawValue)" }
                        }
                        "Registry Key - $($ServiceSetting.RegistryPath)" | Out-File $ReportFile -Append
                        "Registry Value Name - $($ServiceSetting.RegistryValueName)" | Out-File $ReportFile -Append
                        "Registry Value - $RegServiceValue (Raw: $RegRawValue)" | Out-File $ReportFile -Append
                    } else {
                        Write-Log "No Start value found for $($ServiceSetting.SettingName) at $($ServiceSetting.RegistryPath)"
                        "Registry Key - $($ServiceSetting.RegistryPath)" | Out-File $ReportFile -Append
                        "Registry Value Name - $($ServiceSetting.RegistryValueName)" | Out-File $ReportFile -Append
                        "Registry Value - Not set" | Out-File $ReportFile -Append
                    }
                } else {
                    Write-Log "Registry path not found for $($ServiceSetting.SettingName): $($ServiceSetting.RegistryPath)"
                    "Registry Key - $($ServiceSetting.RegistryPath)" | Out-File $ReportFile -Append
                    "Registry Value Name - $($ServiceSetting.RegistryValueName)" | Out-File $ReportFile -Append
                    "Registry Value - Not set" | Out-File $ReportFile -Append
                }
            } else {
                $InvokeArgs = @{ ComputerName = $Computer; ScriptBlock = {
                    param($RegPath, $RegName)
                    if (Test-Path $RegPath) {
                        Get-ItemProperty -Path $RegPath -Name $RegName -ErrorAction Stop
                    }
                }; ArgumentList = @($ServiceSetting.RegistryPath, $ServiceSetting.RegistryValueName); ErrorAction = 'Stop' }
                if ($Credential) { $InvokeArgs['Credential'] = $Credential }
                $RegValueObj = Invoke-Command @InvokeArgs
                if ($RegValueObj -and $RegValueObj.PSObject.Properties.Name -contains $ServiceSetting.RegistryValueName) {
                    $RegRawValue = $RegValueObj.$($ServiceSetting.RegistryValueName)
                    Write-Log "Raw registry value (remote) for $($ServiceSetting.SettingName) at $($ServiceSetting.RegistryPath)\$($ServiceSetting.RegistryValueName): $RegRawValue"
                    $RegServiceValue = switch ($RegRawValue) {
                        2 { "Automatic" }
                        3 { "Manual" }
                        4 { "Disabled" }
                        default { "Unknown ($RegRawValue)" }
                    }
                    "Registry Key - $($ServiceSetting.RegistryPath)" | Out-File $ReportFile -Append
                    "Registry Value Name - $($ServiceSetting.RegistryValueName)" | Out-File $ReportFile -Append
                    "Registry Value - $RegServiceValue (Raw: $RegRawValue)" | Out-File $ReportFile -Append
                } else {
                    Write-Log "No Start value found (remote) for $($ServiceSetting.SettingName) at $($ServiceSetting.RegistryPath)"
                    "Registry Key - $($ServiceSetting.RegistryPath)" | Out-File $ReportFile -Append
                    "Registry Value Name - $($ServiceSetting.RegistryValueName)" | Out-File $ReportFile -Append
                    "Registry Value - Not set" | Out-File $ReportFile -Append
                }
            }
        } catch {
            Write-Log "Error checking registry for $($ServiceSetting.SettingName) - $_"
            "Registry Key - $($ServiceSetting.RegistryPath)" | Out-File $ReportFile -Append
            "Registry Value Name - $($ServiceSetting.RegistryValueName)" | Out-File $ReportFile -Append
            "Registry Value - Not set (check failed - $_)" | Out-File $ReportFile -Append
            $RegServiceValue = "Not set"
        }

        # Determine compliance for service settings
        $ServiceCompliance = if ($ServiceState -eq $ServiceSetting.DesiredState -or $RegServiceValue -eq $ServiceSetting.DesiredState) { "Compliant" } else { "Non-Compliant" }
        "Compliance - $ServiceCompliance" | Out-File $ReportFile -Append
        "" | Out-File $ReportFile -Append
    }

    # Separator for GPO settings
    "" | Out-File $ReportFile -Append
    "=== GPO Settings ===" | Out-File $ReportFile -Append

    # Process GPO hardening settings
    foreach ($Setting in $HardeningSettings) {
        Write-Log "Checking GPO setting - $($Setting.SettingName)"
        "Reference - $($Setting.Reference)" | Out-File $ReportFile -Append
        "Setting - $($Setting.SettingName)" | Out-File $ReportFile -Append
        "Description - $($Setting.Description)" | Out-File $ReportFile -Append
        "Policy Path - $($Setting.PolicyPath)" | Out-File $ReportFile -Append
        "Desired Value - $($Setting.DesiredValue)" | Out-File $ReportFile -Append
        "Default Value - $($Setting.DefaultValue)" | Out-File $ReportFile -Append

        # Check GPResult XML
        $XmlValue = "Not set"
        try {
            $XPath = "//*[local-name()='$($Setting.XmlNode)']"
            if ($Setting.XmlFilter) {
                $FilterField = $Setting.XmlFilter -replace "='.*'", ""
                $FilterValue = $Setting.XmlFilter -replace ".*='(.*)'", '$1'
                $XPath += "[.//*[local-name()='$FilterField' and .='$FilterValue']]"
            }
            $XPath += "[contains(.//*[local-name()='Name'],'$($Setting.XmlName)') or contains(.//*[local-name()='KeyName'],'$($Setting.XmlName)')]"
            Write-Log "Executing XPath for $($Setting.SettingName): $XPath"
            $NameNodes = $GpXml.SelectNodes($XPath)
            if ($NameNodes.Count -eq 0) {
                Write-Log "No nodes found for $($Setting.SettingName) with XPath: $XPath"
            }
            foreach ($Node in $NameNodes) {
                if ($Node.LocalName -eq $Setting.XmlNode) {
                    $ValueNode = $Node.SelectSingleNode("*[local-name()='$($Setting.XmlValueField)']")
                    if (-not $ValueNode -and $Setting.XmlValueField -eq "SettingNumber") {
                        $ValueNode = $Node.SelectSingleNode(".//*[local-name()='Display']/*[local-name()='DisplayBoolean']")
                    }
                    if ($ValueNode) {
                        $XmlValue = if ($Setting.XmlValueField -eq "SettingNumber") {
                            if ($ValueNode.InnerText -eq '1') { "Enabled" } else { "Disabled" }
                        } else {
                            if ($ValueNode.InnerText -eq 'true') { "Enabled" } else { "Disabled" }
                        }
                        # Use KeyName for line number lookup to avoid special characters
                        if ($Setting.XmlFilter) {
                            $FilterValue = $Setting.XmlFilter -replace ".*='(.*)'", '$1'
                            $EscapedPattern = [regex]::Escape($FilterValue)
                            $LineNumber = ($GpXmlLines | Select-String "<[^>]*KeyName>$EscapedPattern</[^>]*>" | Select-Object -First 1).LineNumber
                        } else {
                            $EscapedPattern = [regex]::Escape($Setting.XmlName)
                            $LineNumber = ($GpXmlLines | Select-String "<[^>]*KeyName>$EscapedPattern</[^>]*>|<[^>]*Name>$EscapedPattern</[^>]*>" | Select-Object -First 1).LineNumber
                        }
                        if (-not $LineNumber) {
                            Write-Log "No line number found for $($Setting.SettingName) with pattern: <[^>]*KeyName>$EscapedPattern</[^>]*>"
                        }
                        "GPResult Value - $XmlValue (Found in $GpXmlFile at line $LineNumber)" | Out-File $ReportFile -Append
                        break
                    } else {
                        Write-Log "No value node found for $($Setting.SettingName) under $($Setting.XmlValueField)"
                    }
                }
            }
            if ($XmlValue -eq "Not set") {
                "GPResult Value - Not set" | Out-File $ReportFile -Append
            }
        } catch {
            Write-Log "Error searching XML for $($Setting.SettingName) - $_"
            "GPResult Value - Not set (search error)" | Out-File $ReportFile -Append
        }

        # Check registry for GPO settings
        $RegValue = "Not set"
        if ($Setting.RegistryPath -and $Setting.RegistryValueName) {
            try {
                if ($Computer -eq $env:COMPUTERNAME) {
                    if (Test-Path $Setting.RegistryPath) {
                        $RegValueObj = Get-ItemProperty -Path $Setting.RegistryPath -Name $Setting.RegistryValueName -ErrorAction SilentlyContinue
                        if ($RegValueObj -and $RegValueObj.PSObject.Properties.Name -contains $Setting.RegistryValueName) {
                            $RegRawValue = $RegValueObj.$($Setting.RegistryValueName)
                            if ($Setting.RegistryValueName -eq "FullPrivilegeAuditing") {
                                $RegValue = if ($RegRawValue -eq 1 -or ($RegRawValue -is [byte[]] -and $RegRawValue[0] -eq 1)) { "Enabled" } else { "Disabled" }
                            } else {
                                $RegValue = if ($RegRawValue -eq 1) { "Enabled" } else { "Disabled" }
                            }
                            "Registry Key - $($Setting.RegistryPath)" | Out-File $ReportFile -Append
                            "Registry Value Name - $($Setting.RegistryValueName)" | Out-File $ReportFile -Append
                            "Registry Value - $RegValue (Raw: $(if ($RegRawValue -is [byte[]]) { '0x' + ([BitConverter]::ToString($RegRawValue) -replace '-','') } else { $RegRawValue }))" | Out-File $ReportFile -Append
                        } else {
                            "Registry Key - $($Setting.RegistryPath)" | Out-File $ReportFile -Append
                            "Registry Value Name - $($Setting.RegistryValueName)" | Out-File $ReportFile -Append
                            "Registry Value - Not set" | Out-File $ReportFile -Append
                        }
                    } else {
                        "Registry Key - $($Setting.RegistryPath)" | Out-File $ReportFile -Append
                        "Registry Value Name - $($Setting.RegistryValueName)" | Out-File $ReportFile -Append
                        "Registry Value - Not set" | Out-File $ReportFile -Append
                    }
                } else {
                    $InvokeArgs = @{ ComputerName = $Computer; ScriptBlock = {
                        param($RegPath, $RegName)
                        if (Test-Path $RegPath) {
                            Get-ItemProperty -Path $RegPath -Name $RegName -ErrorAction SilentlyContinue
                        }
                    }; ArgumentList = @($Setting.RegistryPath, $Setting.RegistryValueName); ErrorAction = 'Stop' }
                    if ($Credential) { $InvokeArgs['Credential'] = $Credential }
                    $RegValueObj = Invoke-Command @InvokeArgs
                    if ($RegValueObj -and $RegValueObj.PSObject.Properties.Name -contains $Setting.RegistryValueName) {
                        $RegRawValue = $RegValueObj.$($Setting.RegistryValueName)
                        if ($Setting.RegistryValueName -eq "FullPrivilegeAuditing") {
                            $RegValue = if ($RegRawValue -eq 1 -or ($RegRawValue -is [byte[]] -and $RegRawValue[0] -eq 1)) { "Enabled" } else { "Disabled" }
                        } else {
                            $RegValue = if ($RegRawValue -eq 1) { "Enabled" } else { "Disabled" }
                        }
                        "Registry Key - $($Setting.RegistryPath)" | Out-File $ReportFile -Append
                        "Registry Value Name - $($Setting.RegistryValueName)" | Out-File $ReportFile -Append
                        "Registry Value - $RegValue (Raw: $(if ($RegRawValue -is [byte[]]) { '0x' + ([BitConverter]::ToString($RegRawValue) -replace '-','') } else { $RegRawValue }))" | Out-File $ReportFile -Append
                    } else {
                        "Registry Key - $($Setting.RegistryPath)" | Out-File $ReportFile -Append
                        "Registry Value Name - $($Setting.RegistryValueName)" | Out-File $ReportFile -Append
                        "Registry Value - Not set" | Out-File $ReportFile -Append
                    }
                }
            } catch {
                Write-Log "Error checking registry for $($Setting.SettingName) - $_"
                "Registry Key - $($Setting.RegistryPath)" | Out-File $ReportFile -Append
                "Registry Value Name - $($Setting.RegistryValueName)" | Out-File $ReportFile -Append
                "Registry Value - Not set (check failed - $_)" | Out-File $ReportFile -Append
                $RegValue = "Not set"
            }
        }

        # Determine compliance for GPO settings
        $ComplianceValue = if ($XmlValue -eq "Enabled" -or $RegValue -eq "Enabled") { "Enabled" } else { if ($XmlValue -eq "Not set" -and $RegValue -eq "Not set") { $Setting.DefaultValue } else { "Disabled" } }
        "Compliance - $(if ($ComplianceValue -eq $Setting.DesiredValue) { 'Compliant' } else { 'Non-Compliant' })" | Out-File $ReportFile -Append
        "" | Out-File $ReportFile -Append
    }

    # Section for network adapter settings
    "" | Out-File $ReportFile -Append
    "=== Network Adapter Settings ===" | Out-File $ReportFile -Append

    # Process network adapter settings
    Write-Log "Checking network adapter configurations for $Computer"
    try {
        if ($Computer -eq $env:COMPUTERNAME) {
            $ActiveAdapters = Get-NetAdapter -Physical | Where-Object { $_.MediaType -eq "802.3" -and $_.Status -eq "Up" }
        } else {
            $InvokeArgs = @{ ComputerName = $Computer; ScriptBlock = {
                Get-NetAdapter -Physical | Where-Object { $_.MediaType -eq "802.3" -and $_.Status -eq "Up" }
            }; ErrorAction = 'Stop' }
            if ($Credential) { $InvokeArgs['Credential'] = $Credential }
            $ActiveAdapters = Invoke-Command @InvokeArgs
        }

        if ($ActiveAdapters.Count -eq 0) {
            Write-Log "No active Ethernet adapters found on $Computer"
            "No active Ethernet adapters detected" | Out-File $ReportFile -Append
            "" | Out-File $ReportFile -Append
        } else {
            foreach ($Adapter in $ActiveAdapters) {
                "Adapter - $($Adapter.Name) ($($Adapter.InterfaceDescription))" | Out-File $ReportFile -Append

                # Filter settings based on whether this is a Distributed Engine server
                $IsDEServer = $Computer -match "DE"
                $ApplicableSettings = if ($IsDEServer) {
                    $NetworkSettings
                } else {
                    $NetworkSettings | Where-Object { -not $_.AppliesToDE }
                }

                foreach ($Setting in $ApplicableSettings) {
                    Write-Log "Checking $($Setting.SettingName) for adapter $($Adapter.Name) on $Computer"
                    "Reference - $($Setting.Reference)" | Out-File $ReportFile -Append
                    "Setting - $($Setting.SettingName)" | Out-File $ReportFile -Append
                    "Description - $($Setting.Description)" | Out-File $ReportFile -Append
                    "Desired State - $($Setting.DesiredState)" | Out-File $ReportFile -Append

                    # Check protocol binding state
                    $ProtocolState = "Not found"
                    try {
                        if ($Computer -eq $env:COMPUTERNAME) {
                            $Binding = Get-NetAdapterBinding -Name $Adapter.Name -DisplayName $Setting.ProtocolName -ErrorAction Stop
                            $ProtocolState = if ($Binding.Enabled) { "Enabled" } else { "Disabled" }
                        } else {
                            $InvokeArgs = @{ ComputerName = $Computer; ScriptBlock = {
                                param($AdapterName, $ProtocolDisplayName)
                                Get-NetAdapterBinding -Name $AdapterName -DisplayName $ProtocolDisplayName -ErrorAction Stop
                            }; ArgumentList = @($Adapter.Name, $Setting.ProtocolName); ErrorAction = 'Stop' }
                            if ($Credential) { $InvokeArgs['Credential'] = $Credential }
                            $Binding = Invoke-Command @InvokeArgs
                            $ProtocolState = if ($Binding.Enabled) { "Enabled" } else { "Disabled" }
                        }
                        "Protocol State - $ProtocolState" | Out-File $ReportFile -Append
                    } catch {
                        Write-Log "Error checking $($Setting.SettingName) for $($Adapter.Name) - $_"
                        "Protocol State - Not found (check failed - $_)" | Out-File $ReportFile -Append
                    }

                    # Determine compliance
                    $Compliance = if ($ProtocolState -eq $Setting.DesiredState) { "Compliant" } else { "Non-Compliant" }
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

    # Section for filesystem permissions settings
    "" | Out-File $ReportFile -Append
    "=== Filesystem Permissions Settings ===" | Out-File $ReportFile -Append

    # Process filesystem permissions settings
    Write-Log "Checking filesystem auditing permissions for $Computer"
    foreach ($Setting in $FilesystemSettings) {
        Write-Log "Checking $($Setting.SettingName) for $Computer"
        "Reference - $($Setting.Reference)" | Out-File $ReportFile -Append
        "Setting - $($Setting.SettingName)" | Out-File $ReportFile -Append
        "Description - $($Setting.Description)" | Out-File $ReportFile -Append
        "Path - $($Setting.Path)" | Out-File $ReportFile -Append
        "Principal - $($Setting.Principal)" | Out-File $ReportFile -Append
        "Desired Permissions - $($Setting.DesiredPermissions -join ', ')" | Out-File $ReportFile -Append

        try {
            if ($Computer -eq $env:COMPUTERNAME) {
                $Acl = Get-Acl -Path $Setting.Path -Audit -ErrorAction Stop
            } else {
                $InvokeArgs = @{ ComputerName = $Computer; ScriptBlock = {
                    param($Path)
                    Get-Acl -Path $Path -Audit -ErrorAction Stop
                }; ArgumentList = @($Setting.Path); ErrorAction = 'Stop' }
                if ($Credential) { $InvokeArgs['Credential'] = $Credential }
                $Acl = Invoke-Command @InvokeArgs
            }

            $ActualPermissions = @()
            $AuditRules = $Acl.Audit | Where-Object { $_.IdentityReference -eq $Setting.Principal }
            if ($AuditRules) {
                foreach ($Rule in $AuditRules) {
                    if ($Rule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ExecuteFile) {
                        $ActualPermissions += "Traverse Folder/Execute File"
                    }
                    if ($Rule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ReadData) {
                        $ActualPermissions += "List Folder/Read Data"
                    }
                    if ($Rule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ReadAttributes) {
                        $ActualPermissions += "Read Attributes"
                    }
                    if ($Rule.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ReadExtendedAttributes) {
                        $ActualPermissions += "Read Extended Attributes"
                    }
                }
                # Remove duplicates in case multiple rules grant the same permission
                $ActualPermissions = $ActualPermissions | Sort-Object -Unique
            }

            if ($ActualPermissions.Count -eq 0) {
                "Actual Permissions - None found" | Out-File $ReportFile -Append
            } else {
                "Actual Permissions - $($ActualPermissions -join ', ')" | Out-File $ReportFile -Append
            }

            # Determine compliance
            $MissingPermissions = $Setting.DesiredPermissions | Where-Object { $_ -notin $ActualPermissions }
            $Compliance = if ($MissingPermissions.Count -eq 0 -and $ActualPermissions.Count -ge $Setting.DesiredPermissions.Count) { "Compliant" } else { "Non-Compliant" }
            if ($Compliance -eq "Non-Compliant") {
                if ($MissingPermissions.Count -gt 0) {
                    "Missing Permissions - $($MissingPermissions -join ', ')" | Out-File $ReportFile -Append
                } else {
                    "Note - Extra permissions found" | Out-File $ReportFile -Append
                }
            }
            "Compliance - $Compliance" | Out-File $ReportFile -Append
        } catch {
            Write-Log "Error checking filesystem auditing permissions for $($Setting.SettingName) - $_"
            "Actual Permissions - Check failed ($_)" | Out-File $ReportFile -Append
            "Compliance - Non-Compliant (check failed)" | Out-File $ReportFile -Append
        }
        "" | Out-File $ReportFile -Append
    }

    Write-Log "Completed audit for $Computer. Report saved to $ReportFile"
}

Write-Log "Script execution completed"