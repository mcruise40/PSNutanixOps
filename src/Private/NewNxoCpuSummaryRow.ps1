function NewNxoCpuSummaryRow {
    <#
    .SYNOPSIS
        Builds one row of the cluster/host CPU peak summary.

    .DESCRIPTION
        Internal helper for Get-NxoClusterCpuPeak. For cluster rows the peak is projected onto
        N-1 hosts: MaxCpuPct x Nodes / (Nodes - 1). The status is WARN above the threshold,
        SINGLE NODE for one-node clusters, NO DATA without samples, otherwise OK. Host rows
        carry no projection.

    .PARAMETER PrismCentral
        Prism Central address.

    .PARAMETER Cluster
        Cluster name.

    .PARAMETER Scope
        Cluster or Host.

    .PARAMETER Name
        Name of the cluster or host.

    .PARAMETER Nodes
        Number of hosts in the cluster.

    .PARAMETER Sample
        Time series of hypervisorCpuUsagePpm ({ timestamp, value }).

    .PARAMETER ThresholdPercent
        Threshold for the projected N-1 peak.

    .EXAMPLE
        NewNxoCpuSummaryRow -PrismCentral pc01 -Cluster CL01 -Scope Cluster -Name CL01 -Nodes 4 -Sample $series -ThresholdPercent 80

    .OUTPUTS
        PSCustomObject (PSNutanixOps.ClusterCpuPeak)

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [string]
        $PrismCentral,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Cluster,

        [Parameter(Mandatory)]
        [ValidateSet('Cluster', 'Host')]
        [string]
        $Scope,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Name,

        [Parameter(Mandatory)]
        [ValidateRange(0, 10000)]
        [int]
        $Nodes,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]
        $Sample,

        [Parameter(Mandatory)]
        [ValidateRange(0, 100)]
        [double]
        $ThresholdPercent
    )

    $row = [ordered]@{
        PrismCentral   = $PrismCentral
        Cluster        = $Cluster
        Scope          = $Scope
        Name           = $Name
        Status         = 'NO DATA'
        Nodes          = $Nodes
        MaxCpuPct      = $null
        ProjectedN1Pct = $null
        MaxCpuAt       = $null
        AvgCpuPct      = $null
        Samples        = 0
    }

    $samples = @($Sample | Where-Object { $null -ne $_ -and $null -ne $_.value })
    if ($samples.Count) {
        $stats = $samples.value | Measure-Object -Average -Maximum
        $peak = GetNxoPeakSample -Series $samples
        $maxPct = ConvertToNxoPercent -Ppm $stats.Maximum

        $row.Status = 'OK'
        if ($Scope -eq 'Cluster') {
            if ($Nodes -gt 1) {
                $row.ProjectedN1Pct = [Math]::Round($maxPct * $Nodes / ($Nodes - 1), 2)
                if ($row.ProjectedN1Pct -gt $ThresholdPercent) { $row.Status = 'WARN' }
            } else {
                $row.Status = 'SINGLE NODE'
            }
        }
        $row.MaxCpuPct = $maxPct
        $row.MaxCpuAt = ConvertToNxoLocalTime -Timestamp $peak.timestamp
        $row.AvgCpuPct = ConvertToNxoPercent -Ppm $stats.Average
        $row.Samples = $samples.Count
    }

    $result = [PSCustomObject]$row
    $result.PSObject.TypeNames.Insert(0, 'PSNutanixOps.ClusterCpuPeak')

    return $result
}
