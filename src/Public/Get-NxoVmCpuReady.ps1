function Get-NxoVmCpuReady {
    <#
    .SYNOPSIS
        Summarizes the CPU Ready time of AHV VMs per VM.

    .DESCRIPTION
        Reads the CPU Ready time of all (or selected) AHV VMs of the connected Prism Central
        instances and returns one summary per VM: average, peak, number of samples above a
        threshold and the average CPU usage. With -Raw one object per VM and sample is
        returned instead.

        CPU Ready is the share of time a VM was ready to run but had to wait for the hypervisor
        scheduler. Nutanix guidance (e.g. the SQL Server best practices) treats values above
        5 % as cause for concern. CPU Ready should always be read together with CPU usage.

        The API returns ppm (parts per million, 10'000 ppm = 1 %); the output is in percent.
        With -StatType AVG (default) each sample is the average of one sampling interval, so
        short spikes are smoothed out. Use a smaller -SamplingInterval or -StatType MAX to see
        peaks.

    .PARAMETER Server
        Only query these connected Prism Central instance(s). Default: all connections.

    .PARAMETER VmName
        Only evaluate these VM(s). Case-insensitive, wildcards (*) are supported.

    .PARAMETER CategoryKey
        Category key (e.g. Workload) to select VMs; use together with -CategoryValue.

    .PARAMETER CategoryValue
        Category value (e.g. SQL) used together with -CategoryKey.

    .PARAMETER ClusterName
        Only evaluate VMs on these cluster(s) (Prism Element cluster name).

    .PARAMETER Hours
        Look-back window in hours, ending now. Default: 24. Ignored if -StartTime is given.

    .PARAMETER StartTime
        Explicit start of the window (local time).

    .PARAMETER EndTime
        End of the window (local time). Default: now.

    .PARAMETER SamplingInterval
        Seconds per data point. Default: 300 (5 min), minimum 30.

    .PARAMETER StatType
        Down-sampling per interval: AVG (default), MAX, MIN, LAST.

    .PARAMETER ThresholdPercent
        CPU Ready threshold in percent for Status WARN. Default: 5.

    .PARAMETER IncludePoweredOff
        Also query VMs that are not powered on (they normally return no stats).

    .PARAMETER Raw
        Return one object per VM and sample instead of the per-VM summary.

    .EXAMPLE
        Get-NxoVmCpuReady | Format-Table

        CPU Ready summary of all powered-on VMs, last 24 hours, 5-minute averages.

    .EXAMPLE
        Get-NxoVmCpuReady -ClusterName NTNX-CL01 -Hours 2 -SamplingInterval 30 -StatType MAX | Format-Table

        Peaks in 30-second resolution for the last 2 hours on one cluster.

    .EXAMPLE
        Get-NxoVmCpuReady -CategoryKey Workload -CategoryValue SQL | Where-Object Status -eq 'WARN'

        Only SQL VMs (by category), showing the ones above the threshold.

    .INPUTS
        None

    .OUTPUTS
        PSCustomObject (PSNutanixOps.VmCpuReady or PSNutanixOps.VmCpuReadySample)

    .NOTES
        Field names (hypervisorCpuReadyTimePpm, hypervisorCpuUsagePpm) are taken from the
        official Nutanix VMM SDK (model vmm.v4.ahv.stats.VmStatsTuple). Whether Nutanix
        normalizes the value per vCPU (unlike vCenter's per-VM summation) is not explicitly
        documented.

    .LINK
        Get-NxoClusterCpuPeak
    #>
    [CmdletBinding(DefaultParameterSetName = 'All')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Server,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [Alias('VmNames')]
        [string[]]
        $VmName,

        [Parameter(Mandatory, ParameterSetName = 'ByCategory')]
        [ValidatePattern("^[^']+$")]
        [string]
        $CategoryKey,

        [Parameter(Mandatory, ParameterSetName = 'ByCategory')]
        [ValidatePattern("^[^']+$")]
        [string]
        $CategoryValue,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Alias('ClusterNames')]
        [string[]]
        $ClusterName,

        [Parameter()]
        [ValidateRange(1, 8760)]
        [int]
        $Hours = 24,

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
        [ValidateSet('AVG', 'MAX', 'MIN', 'LAST')]
        [string]
        $StatType = 'AVG',

        [Parameter()]
        [ValidateRange(0, 100)]
        [double]
        $ThresholdPercent = 5,

        [Parameter()]
        [switch]
        $IncludePoweredOff,

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
    $state = @{ UseSelect = $true }
    $thresholdPpm = $ThresholdPercent * 10000

    foreach ($connection in $connections) {
        $pc = $connection.Server
        Write-Verbose ('Prism Central {0} - window {1:yyyy-MM-dd HH:mm} to {2:yyyy-MM-dd HH:mm}, interval {3} s, {4}' -f $pc, $StartTime, $EndTime, $SamplingInterval, $StatType)

        try {
            $vms = @(GetNxoPagedList -Connection $connection -Namespace vmm -Path '/ahv/config/vms' -Activity "$($pc): reading VMs")
        } catch {
            Write-Verbose "$($MyInvocation.MyCommand) failed for '$pc': $_"
            Write-Warning "Skipping Prism Central $pc - VM list failed: $($_.Exception.Message)"
            continue
        }
        $clusterNames = GetNxoNameMap -Connection $connection -Kind Cluster

        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $vms = @($vms | Where-Object {
                    $candidate = $_.name
                    @($VmName | Where-Object { $candidate -like $_ }).Count -gt 0
                })
        } elseif ($PSCmdlet.ParameterSetName -eq 'ByCategory') {
            $categoryExtId = ResolveNxoCategoryExtId -Connection $connection -Key $CategoryKey -Value $CategoryValue
            if (-not $categoryExtId) {
                Write-Warning "No category '$($CategoryKey):$CategoryValue' on $pc - skipping this Prism Central."
                continue
            }
            $vms = @($vms | Where-Object { @($_.categories).extId -contains $categoryExtId })
        }

        if ($ClusterName) {
            if ($clusterNames.Count -eq 0) {
                Write-Warning "Skipping Prism Central $pc - -ClusterName was given, but cluster names could not be resolved."
                continue
            }
            $vms = @($vms | Where-Object {
                    $resolved = $clusterNames[$_.cluster.extId]
                    $resolved -and ($ClusterName -contains $resolved)
                })
        }
        if (-not $IncludePoweredOff) {
            $skipped = @($vms | Where-Object { $_.powerState -ne 'ON' }).Count
            $vms = @($vms | Where-Object { $_.powerState -eq 'ON' })
            if ($skipped) { Write-Verbose "$skipped VM(s) not powered on - skipped (use -IncludePoweredOff to include them)." }
        }
        if (-not $vms.Count) {
            Write-Warning "No matching VMs on $pc."
            continue
        }

        $index = 0
        foreach ($vm in $vms) {
            $index++
            Write-Progress -Activity "CPU Ready on $pc" -Status "$($vm.name) ($index/$($vms.Count))" -PercentComplete ($index / $vms.Count * 100)

            $cluster = ResolveNxoName -Map $clusterNames -ExtId $vm.cluster.extId
            $threads = if ($vm.numThreadsPerCore) { [int]$vm.numThreadsPerCore } else { 1 }
            $vCpus = [int]$vm.numSockets * [int]$vm.numCoresPerSocket * $threads

            try {
                $sampleParam = @{
                    Connection       = $connection
                    VmExtId          = $vm.extId
                    Field            = @('hypervisorCpuReadyTimePpm', 'hypervisorCpuUsagePpm')
                    StartTime        = $StartTime
                    EndTime          = $EndTime
                    SamplingInterval = $SamplingInterval
                    StatType         = $StatType
                    State            = $state
                }
                $samples = @(GetNxoVmStatSample @sampleParam | Where-Object { $null -ne $_.hypervisorCpuReadyTimePpm })
            } catch {
                Write-Verbose "$($MyInvocation.MyCommand) failed for VM '$($vm.name)': $_"
                Write-Warning "Stats for VM '$($vm.name)' on $pc failed: $($_.Exception.Message)"
                continue
            }

            if ($Raw) {
                foreach ($sample in $samples) {
                    $row = [PSCustomObject][ordered]@{
                        PrismCentral = $pc
                        Cluster      = $cluster
                        VM           = $vm.name
                        vCPUs        = $vCpus
                        Timestamp    = ConvertToNxoLocalTime -Timestamp $sample.timestamp
                        CpuReadyPct  = ConvertToNxoPercent -Ppm $sample.hypervisorCpuReadyTimePpm
                        CpuUsagePct  = ConvertToNxoPercent -Ppm $sample.hypervisorCpuUsagePpm
                    }
                    $row.PSObject.TypeNames.Insert(0, 'PSNutanixOps.VmCpuReadySample')
                    $results.Add($row)
                }
                continue
            }

            $summary = [ordered]@{
                PrismCentral   = $pc
                Cluster        = $cluster
                VM             = $vm.name
                Status         = 'NO DATA'
                vCPUs          = $vCpus
                Samples        = $samples.Count
                AvgReadyPct    = $null
                MaxReadyPct    = $null
                AboveThreshold = 0
                AvgCpuUsagePct = $null
                MaxReadyAt     = $null
            }
            if ($samples.Count) {
                $ready = $samples.hypervisorCpuReadyTimePpm | Measure-Object -Average -Maximum
                $peak = $samples | Sort-Object -Property { [double]$_.hypervisorCpuReadyTimePpm } -Descending | Select-Object -First 1
                $usage = @($samples | Where-Object { $null -ne $_.hypervisorCpuUsagePpm })
                $above = @($samples | Where-Object { [double]$_.hypervisorCpuReadyTimePpm -gt $thresholdPpm }).Count

                $summary.Status = if ($above -gt 0) { 'WARN' } else { 'OK' }
                $summary.AvgReadyPct = ConvertToNxoPercent -Ppm $ready.Average
                $summary.MaxReadyPct = ConvertToNxoPercent -Ppm $ready.Maximum
                $summary.AboveThreshold = $above
                $summary.AvgCpuUsagePct = if ($usage.Count) { ConvertToNxoPercent -Ppm ($usage.hypervisorCpuUsagePpm | Measure-Object -Average).Average } else { $null }
                $summary.MaxReadyAt = ConvertToNxoLocalTime -Timestamp $peak.timestamp
            }
            $row = [PSCustomObject]$summary
            $row.PSObject.TypeNames.Insert(0, 'PSNutanixOps.VmCpuReady')
            $results.Add($row)
        }
        Write-Progress -Activity "CPU Ready on $pc" -Completed
    }

    Write-Verbose "Completed $($MyInvocation.MyCommand)"
    if ($Raw) {
        return $results | Sort-Object -Property PrismCentral, Cluster, VM, Timestamp
    }

    $warnCount = @($results | Where-Object Status -EQ 'WARN').Count
    Write-Verbose "$($results.Count) VM(s) evaluated, $warnCount with CPU Ready above $ThresholdPercent % in at least one sample."
    return $results | Sort-Object -Property @{ Expression = { if ($null -eq $_.MaxReadyPct) { -1 } else { $_.MaxReadyPct } }; Descending = $true }, VM
}
