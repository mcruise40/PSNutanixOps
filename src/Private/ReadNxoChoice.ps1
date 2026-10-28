function ReadNxoChoice {
    <#
    .SYNOPSIS
        Prompts until one of the allowed letters is entered.

    .DESCRIPTION
        Internal helper for interactive commands. Only the first character of the answer counts
        (case-insensitive); the allowed letter is returned in upper case.

    .PARAMETER Prompt
        Prompt text.

    .PARAMETER Allowed
        Allowed letters, e.g. L, A, Q.

    .EXAMPLE
        ReadNxoChoice -Prompt '[L]ogin again, change [A]ddress, or [Q]uit' -Allowed L, A, Q

    .OUTPUTS
        System.String

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Prompt,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z]$')]
        [string[]]
        $Allowed
    )

    $letters = @($Allowed | ForEach-Object { $_.ToUpperInvariant() })
    while ($true) {
        $answer = ([string](Read-Host -Prompt $Prompt)).Trim().ToUpperInvariant()
        if ($answer -and $letters -contains $answer.Substring(0, 1)) {
            return $answer.Substring(0, 1)
        }
    }
}
