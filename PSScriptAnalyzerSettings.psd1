@{
    # PSScriptAnalyzer settings - enforced by .github/workflows/lint.yml.
    # Run locally with:
    #   Invoke-ScriptAnalyzer -Path . -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # These are operator-facing scripts run in a console; Write-Host is
        # the intended way to talk to the person running them.
        'PSAvoidUsingWriteHost',
        # Fires on every script's local Write-Log helper: the rule's data
        # lists Write-Log as a built-in of one obscure PowerShell Core build.
        # It is not a built-in on any platform these scripts target.
        'PSAvoidOverwritingBuiltInCmdlets'
    )
}
