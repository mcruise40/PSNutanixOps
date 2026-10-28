function GetNxoLatestSample {
    <#
    .SYNOPSIS
        Returns the newest sample of a time series.

    .DESCRIPTION
        Internal helper. Time series are arrays of { timestamp, value }. Samples without value
        are ignored. Returns $null for an empty series.

    .PARAMETER Series
        The time series.

    .EXAMPLE
        (GetNxoLatestSample -Series $stats['storageUsageBytes']).value

    .OUTPUTS
        PSCustomObject or $null

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]
        $Series
    )

    $samples = @($Series | Where-Object { $null -ne $_ -and $null -ne $_.value })
    if (-not $samples.Count) { return $null }

    return $samples | Sort-Object -Property { ConvertToNxoUtcTime -Timestamp $_.timestamp } | Select-Object -Last 1
}
