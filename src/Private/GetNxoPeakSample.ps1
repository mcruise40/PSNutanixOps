function GetNxoPeakSample {
    <#
    .SYNOPSIS
        Returns the sample with the highest value of a time series.

    .DESCRIPTION
        Internal helper. Time series are arrays of { timestamp, value }. Samples without value
        are ignored. Returns $null for an empty series.

    .PARAMETER Series
        The time series.

    .EXAMPLE
        GetNxoPeakSample -Series $stats['hypervisorCpuUsagePpm']

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

    return $samples | Sort-Object -Property { [double]$_.value } -Descending | Select-Object -First 1
}
