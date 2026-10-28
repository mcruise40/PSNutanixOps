function ConvertToNxoLocalTime {
    <#
    .SYNOPSIS
        Converts an API timestamp to local time.

    .DESCRIPTION
        Internal helper. v4 API timestamps are UTC (ISO-8601). PowerShell's JSON parser turns
        them into DateTime values of kind Utc or leaves them as strings; both are converted to
        local time so they match the Prism UI. A DateTime of kind Unspecified is treated as UTC.
        $null and empty strings return $null.

    .PARAMETER Timestamp
        DateTime, DateTimeOffset or ISO-8601 string.

    .EXAMPLE
        ConvertToNxoLocalTime -Timestamp '2026-10-12T14:18:16Z'

    .OUTPUTS
        System.DateTime or $null

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [object]
        $Timestamp
    )

    $utc = ConvertToNxoUtcTime -Timestamp $Timestamp
    if ($null -eq $utc) { return $null }

    return $utc.ToLocalTime()
}
