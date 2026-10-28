function ConvertToNxoIsoTime {
    <#
    .SYNOPSIS
        Formats a DateTime as ISO-8601 UTC string for API queries.

    .DESCRIPTION
        Internal helper. The v4 stats APIs expect $startTime/$endTime in ISO-8601. UTC with a
        trailing Z avoids URL-encoding problems with '+' offsets.

    .PARAMETER Date
        The date to format. Local and UTC values are both converted correctly.

    .EXAMPLE
        ConvertToNxoIsoTime -Date (Get-Date)
        Returns e.g. 2026-10-28T16:30:00Z

    .OUTPUTS
        System.String

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [datetime]
        $Date
    )

    return $Date.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
}
