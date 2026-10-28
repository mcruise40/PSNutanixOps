function GetNxoClusterEvent {
    <#
    .SYNOPSIS
        Returns the events of one cluster in a time window.

    .DESCRIPTION
        Internal helper for Test-NxoUpgradeReadiness (events during the NCC run). Uses
        monitoring serviceability/events with an OData filter on creationTime; if the filter is
        rejected, the events are paged newest-first and reading stops at the start of the
        window (max. 10 pages).

    .PARAMETER Connection
        Connection object from the connection store.

    .PARAMETER ClusterExtId
        External ID of the cluster.

    .PARAMETER From
        Start of the window.

    .PARAMETER To
        End of the window.

    .EXAMPLE
        GetNxoClusterEvent -Connection $c -ClusterExtId $cl.extId -From $start -To $end

    .OUTPUTS
        PSCustomObject with Time, Type, Service and Message

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]
        $Connection,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ClusterExtId,

        [Parameter(Mandatory)]
        [datetime]
        $From,

        [Parameter(Mandatory)]
        [datetime]
        $To
    )

    $events = $null
    try {
        $filter = [uri]::EscapeDataString(('creationTime ge {0}' -f (ConvertToNxoIsoTime -Date $From)))
        $events = @(GetNxoPagedList -Connection $Connection -Namespace monitoring -Path '/serviceability/events' -Query "`$filter=$filter")
    } catch {
        Write-Verbose "Event filter rejected, paging newest-first: $($_.Exception.Message)"
        $collected = [System.Collections.Generic.List[object]]::new()
        $order = [uri]::EscapeDataString('creationTime desc')
        for ($page = 0; $page -lt 10; $page++) {
            $response = InvokeNxoApi -Connection $Connection -Namespace monitoring -Path ('/serviceability/events?$orderby={0}&$page={1}&$limit=100' -f $order, $page)
            $items = @($response.data | Where-Object { $null -ne $_ })
            foreach ($item in $items) { $collected.Add($item) }
            $oldest = ($items | ForEach-Object { ConvertToNxoLocalTime -Timestamp $_.creationTime } | Measure-Object -Minimum).Minimum
            if ($items.Count -lt 100 -or ($oldest -and $oldest -lt $From)) { break }
        }
        $events = $collected.ToArray()
    }

    $result = foreach ($clusterEvent in @($events | Where-Object { $_.clusterUUID -eq $ClusterExtId -or $_.sourceClusterUUID -eq $ClusterExtId })) {
        $time = ConvertToNxoLocalTime -Timestamp $clusterEvent.creationTime
        if ($time -and $time -ge $From -and $time -le $To) {
            [PSCustomObject]@{
                Time    = $time
                Type    = $clusterEvent.eventType
                Service = $clusterEvent.serviceName
                Message = ExpandNxoAlertText -Text $clusterEvent.message -Parameters $clusterEvent.parameters
            }
        }
    }

    $result | Sort-Object -Property Time
}
