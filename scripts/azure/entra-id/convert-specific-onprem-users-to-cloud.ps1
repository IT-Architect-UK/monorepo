# Install the MSOnline module if not already installed
Install-Module MSOnline -Force

# Connect to Azure AD
Connect-MsolService

# List of user principal names to be converted
$users = @("gamble@it-architect.uk", "help@GeekAlert.IT")

foreach ($user in $users) {
    try {
        # Restore the user (if necessary)
        Restore-MsolUser -UserPrincipalName $user -ErrorAction Stop

        # Clear the ImmutableId
        Get-MsolUser -UserPrincipalName $user | Set-MsolUser -ImmutableId "$null"

        # Output success message
        Write-Output "Successfully converted $user to cloud-only."
    }
    catch {
        # Output error message
        Write-Error "Failed to convert $user: $_"
    }
}

# Verify the changes
foreach ($user in $users) {
    $userInfo = Get-MsolUser -UserPrincipalName $user | Select-Object DisplayName, UserPrincipalName, ImmutableId
    Write-Output $userInfo
}
