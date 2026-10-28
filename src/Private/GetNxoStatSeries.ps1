function GetNxoStatSeries {
    <#
    .SYNOPSIS
        Reads time series from a clustermgmt stats endpoint.

    .DESCRIPTION
        Internal helper. Returns a hashtable metric name -> array of { timestamp, value }.
        The request first uses $select to keep the response small; the API rejects the whole
        $select if a single field is unknown in its revision, so on any error the request is
        repeated without $select. -NoSelect skips the first attempt. Two response shapes are
        handled: data.<metric> = [{timestamp, value}] and data.stats = [{timestamp, <metric>}].
        Metrics the revision does not know are returned as empty arrays.

    .PARAMETER Connection
        Connection object from the connection store.

    .PARAMETER Path
        Stats path below the revision, e.g. /stats/clusters/{extId}.

    .PARAMETER Field
        Metric name(s), e.g. hypervisorCpuUsagePpm.

    .PARAMETER StartTime
        Start of the window.

    .PARAMETER EndTime
        End of the window.

    .PARAMETER SamplingInterval
        Seconds per data point.

    .PARAMETER StatType
        Down-sampling operator: AVG, MAX, MIN or LAST.

    .PARAMETER NoSelect
        Do not use $select.

    .PARAMETER PreferVersion
        Passed to the API call.

    .EXAMPLE
        GetNxoStatSeries -Connection $c -Path "/stats/clusters/$id" -Field hypervisorCpuUsagePpm -StartTime $s -EndTime $e -SamplingInterval 300 -StatType MAX

    .OUTPUTS
        System.Collections.Hashtable

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]
        $Connection,

        [Parameter(Mandatory)]
        [ValidatePattern('^/stats/')]
        [string]
        $Path,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Field,

        [Parameter(Mandatory)]
        [datetime]
        $StartTime,

        [Parameter(Mandatory)]
        [datetime]
        $EndTime,

        [Parameter()]
        [ValidateRange(30, 86400)]
        [int]
        $SamplingInterval = 300,

        [Parameter()]
        [ValidateSet('AVG', 'MAX', 'MIN', 'LAST')]
        [string]
        $StatType = 'AVG',

        [Parameter()]
        [switch]
        $NoSelect,

        [Parameter()]
        [ValidatePattern('^v4\.\d+$')]
        [string]
        $PreferVersion
    )

    $query = '$startTime={0}&$endTime={1}&$samplingInterval={2}&$statType={3}' -f
    [uri]::EscapeDataString((ConvertToNxoIsoTime -Date $StartTime)),
    [uri]::EscapeDataString((ConvertToNxoIsoTime -Date $EndTime)),
    $SamplingInterval, $StatType

    $apiParam = @{ Connection = $Connection; Namespace = 'clustermgmt' }
    if ($PreferVersion) { $apiParam.PreferVersion = $PreferVersion }

    $response = $null
    if (-not $NoSelect) {
        try {
            $select = [uri]::EscapeDataString($Field -join ',')
            $response = InvokeNxoApi @apiParam -Path ('{0}?{1}&$select={2}' -f $Path, $query, $select)
        } catch {
            Write-Verbose "$($MyInvocation.MyCommand): `$select rejected, retrying without it: $_"
        }
    }
    if ($null -eq $response) {
        $response = InvokeNxoApi @apiParam -Path ('{0}?{1}' -f $Path, $query)
    }

    $result = @{}
    foreach ($name in $Field) {
        $series = @(GetNxoPropertyValue -InputObject $response.data -Name $name |
                Where-Object { $null -ne $_ -and $null -ne $_.value })
        if (-not $series.Count -and $response.data.stats) {
            $series = @($response.data.stats | ForEach-Object {
                    $value = GetNxoPropertyValue -InputObject $_ -Name $name
                    if ($null -ne $value) { [PSCustomObject]@{ timestamp = $_.timestamp; value = $value } }
                })
        }
        $result[$name] = $series
    }

    return $result
}
