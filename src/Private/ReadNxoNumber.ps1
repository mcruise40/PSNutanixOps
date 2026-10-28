function ReadNxoNumber {
    <#
    .SYNOPSIS
        Prompts for a whole number within a range.

    .DESCRIPTION
        Internal helper for interactive commands. Repeats the prompt until a number from -Min
        to -Max is entered.

    .PARAMETER Prompt
        Prompt text.

    .PARAMETER Min
        Smallest accepted number.

    .PARAMETER Max
        Largest accepted number.

    .EXAMPLE
        ReadNxoNumber -Prompt 'How many Prism Centrals?' -Min 1 -Max 20

    .OUTPUTS
        System.Int32

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([int])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive prompt: the hint belongs next to Read-Host.')]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Prompt,

        [Parameter(Mandatory)]
        [int]
        $Min,

        [Parameter(Mandatory)]
        [int]
        $Max
    )

    while ($true) {
        $number = 0
        if ([int]::TryParse((ReadNxoText -Prompt $Prompt), [ref]$number) -and $number -ge $Min -and $number -le $Max) {
            return $number
        }
        Write-Host "  Please enter a number from $Min to $Max." -ForegroundColor Yellow
    }
}
