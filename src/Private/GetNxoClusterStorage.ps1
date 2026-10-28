function GetNxoClusterStorage {
    <#
    .SYNOPSIS
        Returns the storage usage of every cluster of a Prism Central.

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup. Reads the newest value (last two
        hours, LAST) of storageUsageBytes, logicalStorageUsageBytes and storageCapacityBytes
        per cluster (clustermgmt stats). Prism Central itself is skipped.

    .PARAMETER Pc
        The Prism Central entry of the run (Label, Connection).

    .EXAMPLE
        GetNxoClusterStorage -Pc $pc

    .OUTPUTS
        PSCustomObject with Pc, Cluster, ClusterExtId, UsedBytes, LogicalUsedBytes, CapacityBytes

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]
        $Pc
    )

    $end = Get-Date
    $fields = @('storageUsageBytes', 'logicalStorageUsageBytes', 'storageCapacityBytes')

    foreach ($cluster in (GetNxoClusterList -Connection $Pc.Connection)) {
        $statParam = @{
            Connection       = $Pc.Connection
            Path             = "/stats/clusters/$($cluster.extId)"
            Field            = $fields
            StartTime        = $end.AddHours(-2)
            EndTime          = $end
            SamplingInterval = 300
            StatType         = 'LAST'
            NoSelect         = $true
        }
        $stats = GetNxoStatSeries @statParam
        $values = @{}
        foreach ($field in $fields) {
            $latest = GetNxoLatestSample -Series $stats[$field]
            $values[$field] = if ($latest) { [long]$latest.value } else { $null }
        }

        [PSCustomObject]@{
            Pc               = $Pc
            Cluster          = if ($cluster.name) { [string]$cluster.name } else { GetNxoShortId -Id $cluster.extId }
            ClusterExtId     = $cluster.extId
            UsedBytes        = $values['storageUsageBytes']
            LogicalUsedBytes = $values['logicalStorageUsageBytes']
            CapacityBytes    = $values['storageCapacityBytes']
        }
    }
}
