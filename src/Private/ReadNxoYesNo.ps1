function ReadNxoYesNo {
    <#
    .SYNOPSIS
        Prompts for yes or no.

    .DESCRIPTION
        Internal helper for interactive commands. Accepts y/yes/j/ja and n/no/nein
        (case-insensitive); Enter alone returns -Default.

    .PARAMETER Prompt
        Prompt text.

    .PARAMETER Default
        Answer for Enter. Default: $true.

    .EXAMPLE
        ReadNxoYesNo -Prompt 'Use the same login?'

    .OUTPUTS
        System.Boolean

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Prompt,

        [Parameter()]
        [bool]
        $Default = $true
    )

    $hint = if ($Default) { 'Y/n' } else { 'y/N' }
    while ($true) {
        $answer = ([string](Read-Host -Prompt ('{0} [{1}]' -f $Prompt, $hint))).Trim()
        if (-not $answer) { return $Default }
        if ($answer -match '^(y|yes|j|ja)$') { return $true }
        if ($answer -match '^(n|no|nein)$') { return $false }
    }
}
