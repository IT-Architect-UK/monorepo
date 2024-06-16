# Install the MSOnline module if not already installed
Install-Module MSOnline -Force

# Connect to Azure AD
Connect-MsolService

# Get all users that were synchronized from on-premise
$syncedUsers = Get-MsolUser -All | Where-Object {$_.ImmutableId -ne $null}

foreach ($user in $syncedUsers) {
    try {
        # Restore the user (if necessary)
        Restore-MsolUser -UserPrincipalName $user.UserPrincipalName -ErrorAction Stop

        # Clear the ImmutableId
        Set-MsolUser -UserPrincipalName $user.UserPrincipalName -ImmutableId "$null"

        # Output success message
        Write-Output "Successfully converted $($user.UserPrincipalName) to cloud-only."
    }
    catch {
        # Output error message
        Write-Error "Failed to convert $($user.UserPrincipalName): $_"
    }
}

# Verify the changes
foreach ($user in $syncedUsers) {
    $userInfo = Get-MsolUser -UserPrincipalName $user.UserPrincipalName | Select-Object DisplayName, UserPrincipalName, ImmutableId
    Write-Output $userInfo
}
