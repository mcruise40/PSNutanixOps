function ReadNxoText {
    <#
    .SYNOPSIS
        Prompts for a non-empty text, with an optional default.

    .DESCRIPTION
        Internal helper for interactive commands. Repeats the prompt until text is entered;
        Enter alone returns -Default when one is given.

    .PARAMETER Prompt
        Prompt text.

    .PARAMETER Default
        Value returned for an empty answer.

    .EXAMPLE
        ReadNxoText -Prompt 'CSV file' -Default '.\list.csv'

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

        [Parameter()]
        [string]
        $Default
    )

    while ($true) {
        $shown = if ($Default) { '{0} [{1}]' -f $Prompt, $Default } else { $Prompt }
        $answer = ([string](Read-Host -Prompt $shown)).Trim()
        if ($answer) { return $answer }
        if ($Default) { return $Default }
    }
}
