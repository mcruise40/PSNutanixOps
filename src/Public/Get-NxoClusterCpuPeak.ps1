function Get-NxoClusterCpuPeak {
    <#
    .SYNOPSIS
        Returns the CPU peak of clusters and hosts and projects the cluster peak onto N-1 hosts.

    .DESCRIPTION
        Reads the hypervisor CPU usage of all (or selected) clusters and their hosts of the
        connected Prism Central instances, determines the peak in the evaluation window and
        projects the cluster peak onto N-1 hosts (one host in maintenance or failed):
        MaxCpuPct x Nodes / (Nodes - 1).

        Intended as a pre-check before rolling upgrades: it shows whether the remaining hosts
        can absorb the load of the busiest period while one host is unavailable. The
        projection assumes homogeneous nodes and an even redistribution of the load;
        additional CVM load during an upgrade is not included. Use it together with
        Get-NxoVmCpuReady - CPU usage alone does not show contention.

        With -StatType MAX (default) each sample is the highest value of one interval, so short
        peaks are kept even with a coarse interval. AvgCpuPct is then the mean of the
        per-interval peaks, not the true average; use -StatType AVG for that.

    .PARAMETER Server
        Only query these connected Prism Central instance(s). Default: all connections.

    .PARAMETER ClusterName
        Only evaluate these cluster(s) (Prism Element cluster name, case-insensitive).

    .PARAMETER Hours
        Look-back window in hours, ending now. Default: 168 (7 days). Ignored if -StartTime is
        given.

    .PARAMETER StartTime
        Explicit start of the window (local time).

    .PARAMETER EndTime
        End of the window (local time). Default: now.

    .PARAMETER SamplingInterval
        Seconds per data point. Default: 300 (5 min), minimum 30.

    .PARAMETER StatType
        Down-sampling per interval: MAX (default), AVG, MIN, LAST.

    .PARAMETER ThresholdPercent
        Threshold for the projected N-1 peak (Status WARN). Default: 80. Rule of thumb, not an
        official Nutanix value.

    .PARAMETER ClusterOnly
        Skip the per-host queries and only return cluster rows.

    .PARAMETER Raw
        Return one object per cluster/host and sample instead of the summary.

    .EXAMPLE
        Get-NxoClusterCpuPeak | Format-Table

        Peak CPU usage of all clusters and hosts over the last 7 days, with N-1 projection.

    .EXAMPLE
        Get-NxoClusterCpuPeak -ClusterName NTNX-CL01 -Hours 24 -SamplingInterval 30 | Format-Table

        Peaks in 30-second resolution for the last 24 hours on one cluster, right before an
        upgrade.

    .INPUTS
        None

    .OUTPUTS
        PSCustomObject (PSNutanixOps.ClusterCpuPeak or PSNutanixOps.ClusterCpuSample)

    .NOTES
        Uses GET /clustermgmt/<revision>/stats/clusters/{id} and .../hosts/{id}. The field
        hypervisorCpuUsagePpm is taken from the official clustermgmt SDK. Entity stats via the
        v4 API need Prism Central pc.2024.1 / AOS 6.8 or later.

    .LINK
        Get-NxoVmCpuReady

    .LINK
        Test-NxoUpgradeReadiness
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Server,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Alias('ClusterNames')]
        [string[]]
        $ClusterName,

        [Parameter()]
        [ValidateRange(1, 8760)]
        [int]
        $Hours = 168,

        [Parameter()]
        [datetime]
        $StartTime,

        [Parameter()]
        [datetime]
        $EndTime = (Get-Date),

        [Parameter()]
        [ValidateRange(30, 86400)]
        [int]
        $SamplingInterval = 300,

        [Parameter()]
        [ValidateSet('MAX', 'AVG', 'MIN', 'LAST')]
        [string]
        $StatType = 'MAX',

        [Parameter()]
        [ValidateRange(0, 100)]
        [double]
        $ThresholdPercent = 80,

        [Parameter()]
        [switch]
        $ClusterOnly,

        [Parameter()]
        [switch]
        $Raw
    )

    Write-Verbose "Starting $($MyInvocation.MyCommand)"
    if (-not $PSBoundParameters.ContainsKey('StartTime')) {
        $StartTime = $EndTime.AddHours(-$Hours)
    }
    if ($StartTime -ge $EndTime) {
        throw [System.ArgumentException]::new('-StartTime must be before -EndTime.', 'StartTime')
    }

    $connections = GetNxoTargetConnection -Server $Server
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $field = 'hypervisorCpuUsagePpm'
    $statParam = @{
        Field            = $field
        StartTime        = $StartTime
        EndTime          = $EndTime
        SamplingInterval = $SamplingInterval
        StatType         = $StatType
    }

    foreach ($connection in $connections) {
        $pc = $connection.Server
        Write-Verbose ('Prism Central {0} - window {1:yyyy-MM-dd HH:mm} to {2:yyyy-MM-dd HH:mm}, interval {3} s, {4}' -f $pc, $StartTime, $EndTime, $SamplingInterval, $StatType)

        try {
            $clusters = @(GetNxoClusterList -Connection $connection -ClusterName $ClusterName)
        } catch {
            Write-Verbose "$($MyInvocation.MyCommand) failed for '$pc': $_"
            Write-Warning "Skipping Prism Central $pc - cluster list failed: $($_.Exception.Message)"
            continue
        }
        if (-not $clusters.Count) {
            Write-Warning "No matching clusters on $pc."
            continue
        }

        $index = 0
        foreach ($cluster in $clusters) {
            $index++
            Write-Progress -Activity "CPU peak on $pc" -Status "$($cluster.name) ($index/$($clusters.Count))" -PercentComplete ($index / $clusters.Count * 100)

            try {
                $hosts = @(GetNxoPagedList -Connection $connection -Namespace clustermgmt -Path "/config/clusters/$($cluster.extId)/hosts")
            } catch {
                Write-Warning "Host list for cluster '$($cluster.name)' on $pc failed: $($_.Exception.Message)"
                continue
            }

            $targets = @([PSCustomObject]@{ Scope = 'Cluster'; Name = [string]$cluster.name; Path = "/stats/clusters/$($cluster.extId)" })
            if (-not $ClusterOnly) {
                $targets += @($hosts | ForEach-Object {
                        [PSCustomObject]@{
                            Scope = 'Host'
                            Name  = if ($_.hostName) { [string]$_.hostName } else { [string]$_.extId }
                            Path  = "/stats/clusters/$($cluster.extId)/hosts/$($_.extId)"
                        }
                    })
            }

            foreach ($target in $targets) {
                try {
                    $series = (GetNxoStatSeries -Connection $connection -Path $target.Path @statParam)[$field]
                } catch {
                    Write-Warning ('Stats for {0} ''{1}'' on {2} failed: {3}' -f $target.Scope.ToLowerInvariant(), $target.Name, $pc, $_.Exception.Message)
                    $series = @()
                }

                if ($Raw) {
                    foreach ($sample in @($series)) {
                        $row = [PSCustomObject][ordered]@{
                            PrismCentral = $pc
                            Cluster      = $cluster.name
                            Scope        = $target.Scope
                            Name         = $target.Name
                            Timestamp    = ConvertToNxoLocalTime -Timestamp $sample.timestamp
                            CpuUsagePct  = ConvertToNxoPercent -Ppm $sample.value
                        }
                        $row.PSObject.TypeNames.Insert(0, 'PSNutanixOps.ClusterCpuSample')
                        $results.Add($row)
                    }
                } else {
                    $rowParam = @{
                        PrismCentral     = $pc
                        Cluster          = [string]$cluster.name
                        Scope            = $target.Scope
                        Name             = $target.Name
                        Nodes            = $hosts.Count
                        Sample           = @($series)
                        ThresholdPercent = $ThresholdPercent
                    }
                    $results.Add((NewNxoCpuSummaryRow @rowParam))
                }
            }
        }
        Write-Progress -Activity "CPU peak on $pc" -Completed
    }

    Write-Verbose "Completed $($MyInvocation.MyCommand)"
    if ($Raw) {
        return $results | Sort-Object -Property PrismCentral, Cluster, Scope, Name, Timestamp
    }

    $clusterRows = @($results | Where-Object Scope -EQ 'Cluster')
    $warnCount = @($clusterRows | Where-Object Status -EQ 'WARN').Count
    Write-Verbose "$($clusterRows.Count) cluster(s) evaluated, $warnCount with a projected N-1 peak above $ThresholdPercent %."

    # Cluster row first, then its hosts by peak descending
    return $results | Sort-Object -Property PrismCentral, Cluster,
    @{ Expression = { if ($_.Scope -eq 'Cluster') { 0 } else { 1 } } },
    @{ Expression = { if ($null -eq $_.MaxCpuPct) { -1 } else { $_.MaxCpuPct } }; Descending = $true }
}
