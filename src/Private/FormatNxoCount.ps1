function FormatNxoCount {
    <#
    .SYNOPSIS
        Formats a count with the singular or plural noun.

    .DESCRIPTION
        Internal helper: "1 recovery point" / "3 recovery points".

    .PARAMETER Count
        The number.

    .PARAMETER Singular
        Noun for 1.

    .PARAMETER Plural
        Noun for other counts. Default: singular + s.

    .EXAMPLE
        FormatNxoCount -Count 3 -Singular 'recovery point'
        Returns 3 recovery points

    .OUTPUTS
        System.String

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [int]
        $Count,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Singular,

        [Parameter()]
        [string]
        $Plural
    )

    if ($Count -eq 1) { return "1 $Singular" }
    if (-not $Plural) { $Plural = "$($Singular)s" }

    return "$Count $Plural"
}
