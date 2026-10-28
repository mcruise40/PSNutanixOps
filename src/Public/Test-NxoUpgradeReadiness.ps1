function Test-NxoUpgradeReadiness {
    <#
    .SYNOPSIS
        Pre-upgrade readiness check for Nutanix AHV clusters, with an HTML report per cluster.

    .DESCRIPTION
        Verifies that one host can be taken out of operation (maintenance mode for LCM updates)
        without resource shortages, records open alerts with the engineer's justification and
        writes an HTML report per cluster that can be attached to the change.

        Checks per cluster:
          1. Cluster and host state  - no upgrade running, no host already in maintenance
          2. Data resiliency         - current fault tolerance >= configured fault tolerance
          3. Storage                 - usage in percent of the resilient capacity
          4. HA reservation          - memory reserved for a host failure (Guarantee mode).
                                       Only exposed from API v4.3 on; otherwise the engineer
                                       checks the UI and confirms it
          5. Memory with N-1         - configured memory of running VMs vs. host memory minus
                                       CVM, without the largest host
          6. CPU with N-1            - cluster CPU peak projected onto N-1 hosts (main criterion)
          7. CPU Ready               - highest CPU Ready per VM in the window (warning only)
          8. GPU with N-1            - GPU profiles in use vs. capacity without the GPU host
                                       with the most cards
          9. Non-migratable VMs      - affinity, GPU passthrough, PCIe devices, ...
         10. NCC health checks       - started by the command, result recorded
         11. Open alerts             - Critical and Warning; acknowledged ones for information

        Rating: any FAIL -> NO-GO; any WARN -> GO WITH RESERVATIONS (the engineer enters a
        justification per warning); else GO. Open alerts never cause NO-GO on their own.
        The upgrade itself is not started.

        The command is interactive by default (HA reservation confirmation, NCC email
        recipient, justifications). Use -NonInteractive for unattended runs.

    .PARAMETER Server
        Only check clusters of these connected Prism Central instance(s). Default: all.

    .PARAMETER ClusterName
        Only check these cluster(s). Recommended, as a change normally covers one cluster.

    .PARAMETER ChangeId
        Change or ticket number, printed in the report and used in its file name.

    .PARAMETER Engineer
        Name of the engineer running the check. Default: the current user.

    .PARAMETER Hours
        Look-back window for CPU peak and CPU Ready in hours. Default: 168 (7 days).

    .PARAMETER CpuThresholdPercent
        Maximum projected N-1 CPU peak; above -> FAIL. Default: 80.

    .PARAMETER MemoryThresholdPercent
        Maximum memory of running VMs in percent of the N-1 capacity; above -> FAIL. Default: 95.

    .PARAMETER StorageThresholdPercent
        Maximum storage usage in percent of the resilient capacity; above -> FAIL. Default: 75.

    .PARAMETER CpuReadyThresholdPercent
        CPU Ready threshold per VM; VMs above it -> WARN. Default: 5.

    .PARAMETER SkipNcc
        Do not start the NCC health checks.

    .PARAMETER NccTimeoutMinutes
        Maximum time to wait for the NCC run per cluster. Default: 60.

    .PARAMETER NccReportRecipient
        Email address(es) for the NCC run summary. Without it the alert email configuration of
        Prism Central is used.

    .PARAMETER SkipCpuReady
        Skip the CPU Ready evaluation (faster on large environments).

    .PARAMETER NonInteractive
        Do not prompt. Warnings are reported as "no justification provided".

    .PARAMETER ReportFolder
        Folder for the HTML reports. Default: current directory.

    .PARAMETER PreferApiVersion
        API revision to try first. Default: v4.3 (needed for haMemoryReservedBytes); falls back
        to v4.2, v4.1, v4.0.

    .EXAMPLE
        Test-NxoUpgradeReadiness -ClusterName NTNX-CL01 -ChangeId CHG0012345

        Full check of one cluster including NCC, with an HTML report for the change.

    .EXAMPLE
        Test-NxoUpgradeReadiness -SkipNcc -NonInteractive | Format-Table Cluster, Verdict, Check, Result, Value

        Quick check of all clusters without NCC and without prompts.

    .INPUTS
        None

    .OUTPUTS
        PSCustomObject (PSNutanixOps.UpgradeReadinessCheck)

    .NOTES
        Approximations:
        - Resilient capacity = storage capacity minus the capacity of the largest host(s) (one
          host for FT1, two for FT2). Prism's own value may differ slightly.
        - Memory N-1 counts VMs with memory overcommit with their full size.
        - GPU N-1 assumes the profile capacity is spread evenly across all GPU cards.

    .LINK
        Get-NxoClusterCpuPeak
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive console tool: progress and the verdict are shown between the prompts for the engineer, not written to an output stream.')]
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
        [ValidateNotNullOrEmpty()]
        [string]
        $ChangeId,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $Engineer = $(if ($env:USERDOMAIN) { '{0}\{1}' -f $env:USERDOMAIN, $env:USERNAME } else { [Environment]::UserName }),

        [Parameter()]
        [ValidateRange(1, 8760)]
        [int]
        $Hours = 168,

        [Parameter()]
        [ValidateRange(1, 100)]
        [double]
        $CpuThresholdPercent = 80,

        [Parameter()]
        [ValidateRange(1, 100)]
        [double]
        $MemoryThresholdPercent = 95,

        [Parameter()]
        [ValidateRange(1, 100)]
        [double]
        $StorageThresholdPercent = 75,

        [Parameter()]
        [ValidateRange(0, 100)]
        [double]
        $CpuReadyThresholdPercent = 5,

        [Parameter()]
        [switch]
        $SkipNcc,

        [Parameter()]
        [ValidateRange(1, 480)]
        [int]
        $NccTimeoutMinutes = 60,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Alias('NccReportRecipients')]
        [string[]]
        $NccReportRecipient,

        [Parameter()]
        [switch]
        $SkipCpuReady,

        [Parameter()]
        [switch]
        $NonInteractive,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ReportFolder = (Get-Location).Path,

        [Parameter()]
        [ValidatePattern('^v4\.\d+$')]
        [Alias('ApiVersion')]
        [string]
        $PreferApiVersion = 'v4.3'
    )

    Write-Verbose "Starting $($MyInvocation.MyCommand)"
    $connections = GetNxoTargetConnection -Server $Server

    $endTime = Get-Date
    $startTime = $endTime.AddHours(-$Hours)
    $recentStart = $endTime.AddHours(-6)   # short window for current values (capacities, usage)

    if (-not (Test-Path -LiteralPath $ReportFolder)) {
        $null = New-Item -ItemType Directory -Path $ReportFolder
    }
    $ReportFolder = (Resolve-Path -LiteralPath $ReportFolder).Path

    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $nccState = @{ Recipients = @($NccReportRecipient | Where-Object { $_ }); Asked = $false }
    $checkCache = @{}
    $haUiPath = 'Prism Element > Settings > Manage VM High Availability > "Enable HA Reservation"'

    foreach ($connection in $connections) {
        $pc = $connection.Server
        Write-Host ('Prism Central {0} - CPU window {1:yyyy-MM-dd HH:mm} to {2:yyyy-MM-dd HH:mm}' -f $pc, $startTime, $endTime) -ForegroundColor Cyan

        try {
            $clusters = @(GetNxoClusterList -Connection $connection -ClusterName $ClusterName -PreferVersion $PreferApiVersion)
        } catch {
            Write-Verbose "$($MyInvocation.MyCommand) failed for '$pc': $_"
            Write-Warning "Skipping Prism Central $pc - cluster list failed: $($_.Exception.Message)"
            continue
        }
        if (-not $clusters.Count) {
            Write-Warning "No matching clusters on $pc."
            continue
        }

        # --- Start NCC on all target clusters first (runs while the data is collected) ---
        $nccTasks = @{}
        if (-not $SkipNcc) {
            foreach ($cluster in $clusters) {
                $nccTasks[$cluster.extId] = StartNxoNccCheck -Connection $connection -ClusterExtId $cluster.extId -ClusterName $cluster.name -State $nccState -NonInteractive:$NonInteractive
                if ($nccTasks[$cluster.extId].TaskId) { Write-Host "  NCC started on $($cluster.name)" -ForegroundColor DarkGray }
            }
        }

        # --- VMs (once per Prism Central) ---
        try {
            $allVms = @(GetNxoPagedList -Connection $connection -Namespace vmm -Path '/ahv/config/vms' -PreferVersion $PreferApiVersion)
        } catch {
            Write-Warning "VM list on $pc failed: $($_.Exception.Message)"
            $allVms = @()
        }

        # --- CPU Ready (once per Prism Central, list endpoint, hourly maximum) ---
        $cpuReadyByVm = @{}
        $cpuReadyError = $null
        if (-not $SkipCpuReady) {
            try {
                $query = '$startTime={0}&$endTime={1}&$samplingInterval=3600&$statType=MAX&$select={2}' -f
                [uri]::EscapeDataString((ConvertToNxoIsoTime -Date $startTime)),
                [uri]::EscapeDataString((ConvertToNxoIsoTime -Date $endTime)),
                [uri]::EscapeDataString('stats/timestamp,stats/hypervisorCpuReadyTimePpm')
                foreach ($vmStats in (GetNxoPagedList -Connection $connection -Namespace vmm -Path '/ahv/stats/vms' -Query $query -PreferVersion $PreferApiVersion)) {
                    $values = @($vmStats.stats | Where-Object { $null -ne $_.hypervisorCpuReadyTimePpm })
                    if ($values.Count) {
                        $peak = $values | Sort-Object -Property { [double]$_.hypervisorCpuReadyTimePpm } -Descending | Select-Object -First 1
                        $cpuReadyByVm[$vmStats.extId] = [PSCustomObject]@{ Ppm = $peak.hypervisorCpuReadyTimePpm; At = ConvertToNxoLocalTime -Timestamp $peak.timestamp }
                    }
                }
            } catch {
                $cpuReadyError = $_.Exception.Message
                Write-Warning "CPU Ready stats on $pc failed: $cpuReadyError"
            }
        }

        foreach ($cluster in $clusters) {
            Write-Host "Checking cluster $($cluster.name)" -ForegroundColor Cyan
            $checks = [System.Collections.Generic.List[object]]::new()
            $extra = @{ AckAlerts = @(); NonMigratable = @(); CpuReady = @(); Hosts = @(); Info = [ordered]@{}; Ncc = $null }
            $clusterVms = @($allVms | Where-Object { $_.cluster.extId -eq $cluster.extId })
            $runningVms = @($clusterVms | Where-Object { $_.powerState -eq 'ON' })
            $faultTolerance = $cluster.config.faultToleranceState

            $extra.Info['AOS version'] = $cluster.config.buildInfo.version
            $extra.Info['Redundancy factor'] = $cluster.config.redundancyFactor
            $extra.Info['VMs (running / total)'] = '{0} / {1}' -f $runningVms.Count, $clusterVms.Count

            # --- Hosts ---
            try {
                $hosts = @(GetNxoPagedList -Connection $connection -Namespace clustermgmt -Path "/config/clusters/$($cluster.extId)/hosts" -PreferVersion $PreferApiVersion)
            } catch {
                Write-Warning "Host list for $($cluster.name) failed: $($_.Exception.Message)"
                $hosts = @()
            }
            $vmHosts = @($hosts | Where-Object { $_.hostType -ne 'STORAGE_ONLY' })

            # --- Cluster stats ---
            $cpuSeries = @()
            $now = @{}
            $statBase = @{ Connection = $connection; Path = "/stats/clusters/$($cluster.extId)"; SamplingInterval = 300; PreferVersion = $PreferApiVersion }
            try {
                $cpuSeries = (GetNxoStatSeries @statBase -Field hypervisorCpuUsagePpm -StatType MAX -StartTime $startTime -EndTime $endTime)['hypervisorCpuUsagePpm']
                $nowFields = @('storageCapacityBytes', 'storageUsageBytes', 'memoryCapacityBytes', 'totalMemoryAllottedToVmBytes',
                    'haMemoryReservedBytes', 'cpuOvercommitRatioPpm', 'memoryOvercommitRatioPpm', 'aggregateVmConfiguredVcpus')
                # No $select: several of these fields only exist from API revision v4.3 on
                $current = GetNxoStatSeries @statBase -Field $nowFields -StatType LAST -StartTime $recentStart -EndTime $endTime -NoSelect
                foreach ($field in $nowFields) { $now[$field] = (GetNxoLatestSample -Series $current[$field]).value }
            } catch {
                Write-Warning "Cluster stats for $($cluster.name) failed: $($_.Exception.Message)"
            }

            # --- CVMs (memory per host, subtracted from the capacity available to VMs) ---
            $cvmMemoryByHost = @{}
            $cvmNames = @()
            try {
                foreach ($cvm in (GetNxoPagedList -Connection $connection -Namespace clustermgmt -Path "/config/clusters/$($cluster.extId)/cvms" -PreferVersion $PreferApiVersion)) {
                    if ($cvm.nodeExtId) { $cvmMemoryByHost[$cvm.nodeExtId] = [double]$cvm.memorySizeBytes }
                    if ($cvm.name) { $cvmNames += $cvm.name }
                }
            } catch {
                Write-Verbose "CVM list for $($cluster.name) not available: $($_.Exception.Message)"
            }
            $userVms = @($runningVms | Where-Object { $cvmNames -notcontains $_.name -and $_.name -notmatch '^NTNX-.*-CVM$' })

            # --- Host stats ---
            $hostRows = @(foreach ($hostItem in $hosts) {
                    $hostStat = @{}
                    $hostPeak = $null
                    $hostBase = @{ Connection = $connection; Path = "/stats/clusters/$($cluster.extId)/hosts/$($hostItem.extId)"; SamplingInterval = 300; PreferVersion = $PreferApiVersion }
                    try {
                        $capacityFields = @('memoryCapacityBytes', 'storageCapacityBytes')
                        $capacity = GetNxoStatSeries @hostBase -Field $capacityFields -StatType LAST -StartTime $recentStart -EndTime $endTime -NoSelect
                        foreach ($field in $capacityFields) { $hostStat[$field] = (GetNxoLatestSample -Series $capacity[$field]).value }
                        $usage = GetNxoStatSeries @hostBase -Field hypervisorCpuUsagePpm -StatType MAX -StartTime $startTime -EndTime $endTime
                        $hostPeak = GetNxoPeakSample -Series $usage['hypervisorCpuUsagePpm']
                    } catch {
                        Write-Warning "Host stats for $($hostItem.hostName) failed: $($_.Exception.Message)"
                    }
                    $gpuNames = @($hostItem.gpuList | Where-Object { $_ -and ([string]$_).Trim() }) | Group-Object | ForEach-Object {
                        if ($_.Count -gt 1) { '{0}x {1}' -f $_.Count, $_.Name } else { $_.Name }
                    }
                    [PSCustomObject][ordered]@{
                        Host           = $hostItem.hostName
                        Type           = $hostItem.hostType
                        NodeStatus     = $hostItem.nodeStatus
                        Maintenance    = $hostItem.maintenanceState
                        RebootPending  = $hostItem.isRebootPending
                        MemoryBytes    = if ($hostStat.memoryCapacityBytes) { $hostStat.memoryCapacityBytes } else { $hostItem.memorySizeBytes }
                        CvmMemoryBytes = $cvmMemoryByHost[$hostItem.extId]
                        StorageBytes   = $hostStat.storageCapacityBytes
                        Cores          = $hostItem.numberOfCpuCores
                        Threads        = $hostItem.numberOfCpuThreads
                        MaxCpuPct      = if ($hostPeak) { ConvertToNxoPercent -Ppm $hostPeak.value } else { $null }
                        MaxCpuAt       = if ($hostPeak) { ConvertToNxoLocalTime -Timestamp $hostPeak.timestamp } else { $null }
                        Gpus           = GetNxoItemCount -Value $hostItem.gpuList
                        GpuNames       = @($gpuNames) -join ', '
                    }
                })
            $extra.Hosts = $hostRows

            # ===== 1. Cluster and host state =====
            $inMaintenance = @($hostRows | Where-Object { $_.Maintenance -and $_.Maintenance -notmatch '^(normal|none)$' })
            $notNormal = @($hostRows | Where-Object { $_.NodeStatus -and $_.NodeStatus -ne 'NORMAL' })
            $upgradeStatus = $cluster.upgradeStatus
            if ($upgradeStatus -in @('PENDING', 'DOWNLOADING', 'QUEUED', 'PREUPGRADE', 'UPGRADING', 'SCHEDULED')) {
                AddNxoCheck -List $checks -Check 'Cluster and host state' -Result FAIL -Value "Upgrade status $upgradeStatus" -Threshold 'No upgrade in progress' -Detail 'An upgrade is already running or scheduled on this cluster.'
            } elseif ($inMaintenance.Count -or $notNormal.Count) {
                $names = (@($inMaintenance) + @($notNormal) | ForEach-Object { $_.Host } | Select-Object -Unique) -join ', '
                AddNxoCheck -List $checks -Check 'Cluster and host state' -Result FAIL -Value "Not normal: $names" -Threshold 'All hosts in normal operation' -Detail 'At least one host is already in maintenance or not in NORMAL state - the cluster has no N-1 headroom left.'
            } else {
                $reboot = @($hostRows | Where-Object RebootPending | ForEach-Object { $_.Host })
                $detail = if ($reboot.Count) { "Reboot pending on: $($reboot -join ', ')" } else { 'All hosts in normal operation.' }
                AddNxoCheck -List $checks -Check 'Cluster and host state' -Result PASS -Value "$($hosts.Count) host(s)" -Threshold 'All hosts in normal operation' -Detail $detail
            }

            # ===== 2. Data resiliency =====
            if ($faultTolerance -and $null -ne $faultTolerance.currentMaxFaultTolerance) {
                $desired = if ($null -ne $faultTolerance.desiredMaxFaultTolerance) { $faultTolerance.desiredMaxFaultTolerance } else { 1 }
                $result = if ($faultTolerance.currentMaxFaultTolerance -ge $desired -and $faultTolerance.currentMaxFaultTolerance -ge 1) { 'PASS' } else { 'FAIL' }
                AddNxoCheck -List $checks -Check 'Data resiliency' -Result $result -Value "FT $($faultTolerance.currentMaxFaultTolerance) (desired FT $desired)" -Threshold 'Current FT >= desired FT' -Detail "Domain awareness: $($faultTolerance.domainAwarenessLevel)"
            } else {
                AddNxoCheck -List $checks -Check 'Data resiliency' -Result WARN -Value 'n/a' -Threshold 'Current FT >= desired FT' -Detail 'Fault tolerance state not returned by the API - check the Data Resiliency widget in Prism manually.'
            }

            # ===== 3. Storage vs. resilient capacity =====
            $ftLevel = if ($faultTolerance -and $faultTolerance.desiredMaxFaultTolerance) { [int]$faultTolerance.desiredMaxFaultTolerance } else { 1 }
            $hostStorage = @($hostRows | Where-Object { $_.Type -ne 'COMPUTE_ONLY' -and $_.StorageBytes } | Sort-Object -Property StorageBytes -Descending)
            if ($now.storageCapacityBytes -and $null -ne $now.storageUsageBytes -and $hostStorage.Count -gt $ftLevel) {
                $lost = ($hostStorage | Select-Object -First $ftLevel | Measure-Object -Property StorageBytes -Sum).Sum
                $resilient = [double]$now.storageCapacityBytes - $lost
                $percent = [Math]::Round([double]$now.storageUsageBytes / $resilient * 100, 1)
                $result = if ($percent -gt $StorageThresholdPercent) { 'FAIL' } else { 'PASS' }
                $detail = 'Used {0} of {1} resilient capacity (total {2}, FT{3})' -f (FormatNxoSize -Bytes $now.storageUsageBytes -Unit TiB), (FormatNxoSize -Bytes $resilient -Unit TiB), (FormatNxoSize -Bytes $now.storageCapacityBytes -Unit TiB), $ftLevel
                AddNxoCheck -List $checks -Check 'Storage (resilient capacity)' -Result $result -Value "$percent %" -Threshold "<= $StorageThresholdPercent %" -Detail $detail
            } else {
                AddNxoCheck -List $checks -Check 'Storage (resilient capacity)' -Result WARN -Value 'n/a' -Threshold "<= $StorageThresholdPercent %" -Detail 'Storage capacity could not be determined - check the storage summary in Prism manually.'
            }

            # ===== 4. HA reservation =====
            if ($null -ne $now.haMemoryReservedBytes) {
                if ([double]$now.haMemoryReservedBytes -gt 0) {
                    AddNxoCheck -List $checks -Check 'HA reservation' -Result PASS -Value ('{0} reserved' -f (FormatNxoSize -Bytes $now.haMemoryReservedBytes -Unit GiB)) -Threshold 'Enabled' -Detail 'Memory is reserved to restart the VMs of a failed host (Guarantee mode).'
                } else {
                    AddNxoCheck -List $checks -Check 'HA reservation' -Result WARN -Value 'Not enabled' -Threshold 'Enabled' -Detail 'No memory is reserved for a host failure (best effort). The memory check shows whether the VMs still fit on N-1.'
                }
            } else {
                $apiNote = 'Not exposed by the API (clustermgmt {0}; requires v4.3).' -f $connection.NamespaceVersion["clustermgmt@$PreferApiVersion"]
                $answer = ReadNxoHaReservation -ClusterName $cluster.name -UiPath $haUiPath -NonInteractive:$NonInteractive
                $stamp = '{0} on {1:yyyy-MM-dd HH:mm}' -f $Engineer, (Get-Date)
                switch ($answer) {
                    'Y' { AddNxoCheck -List $checks -Check 'HA reservation' -Result PASS -Value 'Enabled (confirmed manually)' -Threshold 'Enabled' -Detail "$apiNote Checked in the UI ($haUiPath) and confirmed by $stamp." }
                    'N' { AddNxoCheck -List $checks -Check 'HA reservation' -Result WARN -Value 'Not enabled (confirmed manually)' -Threshold 'Enabled' -Detail "$apiNote Checked in the UI and reported as not enabled by $stamp. No memory is reserved for a host failure (best effort); the memory check shows whether the VMs still fit on N-1." }
                    default {
                        $reason = if ($NonInteractive) { ' (-NonInteractive)' } else { '' }
                        AddNxoCheck -List $checks -Check 'HA reservation' -Result WARN -Value 'Not confirmed' -Threshold 'Enabled' -Detail "$apiNote The setting was not checked during this run$reason. Check in the UI: $haUiPath."
                    }
                }
            }

            # ===== 5. Memory with N-1 =====
            $memoryHosts = @($hostRows | Where-Object { $_.Type -ne 'STORAGE_ONLY' -and $_.MemoryBytes })
            $vmMemory = [double](($userVms | Measure-Object -Property memorySizeBytes -Sum).Sum)
            if ($memoryHosts.Count -gt 1) {
                $available = @($memoryHosts | ForEach-Object { [double]$_.MemoryBytes - $(if ($_.CvmMemoryBytes) { [double]$_.CvmMemoryBytes } else { 0 }) })
                $capacityTotal = ($available | Measure-Object -Sum).Sum
                $capacityN1 = $capacityTotal - ($available | Measure-Object -Maximum).Maximum
                $percent = [Math]::Round($vmMemory / $capacityN1 * 100, 1)
                $result = if ($percent -gt $MemoryThresholdPercent) { 'FAIL' } else { 'PASS' }
                $overcommit = @($userVms | Where-Object isMemoryOvercommitEnabled).Count
                $cvmNote = if ($cvmMemoryByHost.Count) { 'CVM memory subtracted' } else { 'CVM memory could not be read and is NOT subtracted' }
                $detail = '{0} configured on {1} running VM(s), N-1 capacity {2} (all hosts {3}, {4}). VMs with memory overcommit: {5} (counted with full size)' -f (FormatNxoSize -Bytes $vmMemory -Unit GiB), $userVms.Count, (FormatNxoSize -Bytes $capacityN1 -Unit GiB), (FormatNxoSize -Bytes $capacityTotal -Unit GiB), $cvmNote, $overcommit
                AddNxoCheck -List $checks -Check 'Memory with N-1' -Result $result -Value "$percent %" -Threshold "<= $MemoryThresholdPercent %" -Detail $detail
            } else {
                AddNxoCheck -List $checks -Check 'Memory with N-1' -Result FAIL -Value 'Single host' -Threshold 'At least 2 hosts' -Detail 'Single-node cluster - VMs must be shut down for the upgrade.'
            }
            $hostMemory = ($memoryHosts | Measure-Object -Property MemoryBytes -Sum).Sum
            if ($hostMemory) {
                $extra.Info['Memory allocation (running VMs : hosts)'] = '{0:N2} : 1 ({1} of {2})' -f ($vmMemory / $hostMemory), (FormatNxoSize -Bytes $vmMemory -Unit GiB), (FormatNxoSize -Bytes $hostMemory -Unit GiB)
            }

            # ===== 6. CPU with N-1 =====
            $nodeCount = $vmHosts.Count
            $peak = GetNxoPeakSample -Series $cpuSeries
            if ($peak -and $nodeCount -gt 1) {
                $maxPercent = ConvertToNxoPercent -Ppm $peak.value
                $projected = [Math]::Round($maxPercent * $nodeCount / ($nodeCount - 1), 1)
                $result = if ($projected -gt $CpuThresholdPercent) { 'FAIL' } else { 'PASS' }
                $detail = 'Cluster peak {0} % at {1:yyyy-MM-dd HH:mm}, {2} hosts -> projected onto {3}' -f $maxPercent, (ConvertToNxoLocalTime -Timestamp $peak.timestamp), $nodeCount, ($nodeCount - 1)
                AddNxoCheck -List $checks -Check 'CPU peak with N-1' -Result $result -Value "$projected %" -Threshold "<= $CpuThresholdPercent %" -Detail $detail
            } elseif ($nodeCount -le 1) {
                AddNxoCheck -List $checks -Check 'CPU peak with N-1' -Result FAIL -Value 'Single host' -Threshold 'At least 2 hosts' -Detail 'Single-node cluster - VMs must be shut down for the upgrade.'
            } else {
                AddNxoCheck -List $checks -Check 'CPU peak with N-1' -Result WARN -Value 'n/a' -Threshold "<= $CpuThresholdPercent %" -Detail 'No CPU usage data in the window.'
            }
            $vCpus = ($userVms | ForEach-Object { [int]$_.numSockets * [int]$_.numCoresPerSocket * $(if ($_.numThreadsPerCore) { [int]$_.numThreadsPerCore } else { 1 }) } | Measure-Object -Sum).Sum
            $cores = ($vmHosts | ForEach-Object { [int]$_.numberOfCpuCores } | Measure-Object -Sum).Sum
            if ($cores) {
                $extra.Info['vCPU : physical core ratio (running VMs)'] = '{0:N2} : 1 ({1} vCPU on {2} cores)' -f ($vCpus / $cores), $vCpus, $cores
                if ($nodeCount -gt 1) {
                    $coresN1 = $cores - ($vmHosts | ForEach-Object { [int]$_.numberOfCpuCores } | Measure-Object -Maximum).Maximum
                    if ($coresN1) { $extra.Info['vCPU : physical core ratio with N-1'] = '{0:N2} : 1' -f ($vCpus / $coresN1) }
                }
            }
            if ($null -ne $now.aggregateVmConfiguredVcpus) { $extra.Info['Configured vCPUs'] = $now.aggregateVmConfiguredVcpus }

            # ===== 7. CPU Ready =====
            if ($SkipCpuReady) {
                AddNxoCheck -List $checks -Check 'CPU Ready' -Result SKIPPED -Value '-' -Threshold "<= $CpuReadyThresholdPercent %" -Detail 'Skipped (-SkipCpuReady).'
            } elseif ($cpuReadyError) {
                AddNxoCheck -List $checks -Check 'CPU Ready' -Result SKIPPED -Value 'n/a' -Threshold "<= $CpuReadyThresholdPercent %" -Detail "CPU Ready stats could not be read: $cpuReadyError"
            } else {
                $ready = @(foreach ($vm in $runningVms) {
                        $value = $cpuReadyByVm[$vm.extId]
                        if ($value) { [PSCustomObject]@{ VM = $vm.name; MaxReadyPct = ConvertToNxoPercent -Ppm $value.Ppm; At = $value.At } }
                    }) | Sort-Object -Property MaxReadyPct -Descending
                $ready = @($ready)
                $extra.CpuReady = @($ready | Select-Object -First 10)
                $above = @($ready | Where-Object { $_.MaxReadyPct -gt $CpuReadyThresholdPercent })
                $top = if ($ready.Count) { $ready[0].MaxReadyPct } else { 0 }
                if ($above.Count) {
                    $list = ($above | Select-Object -First 5 | ForEach-Object { '{0} ({1} %)' -f $_.VM, $_.MaxReadyPct }) -join ', '
                    AddNxoCheck -List $checks -Check 'CPU Ready' -Result WARN -Value "$($above.Count) VM(s), max $top %" -Threshold "<= $CpuReadyThresholdPercent %" -Detail "Above threshold: $list"
                } else {
                    AddNxoCheck -List $checks -Check 'CPU Ready' -Result PASS -Value "max $top %" -Threshold "<= $CpuReadyThresholdPercent %" -Detail "$($ready.Count) running VM(s) with CPU Ready data, none above the threshold (contention already present would get worse with N-1)."
                }
            }

            # ===== 8. GPU with N-1 =====
            $gpuVms = @($runningVms | Where-Object { (GetNxoItemCount -Value $_.gpus) -gt 0 })
            if (-not $gpuVms.Count) {
                AddNxoCheck -List $checks -Check 'GPU with N-1' -Result PASS -Value 'No GPU VMs' -Threshold '-' -Detail 'No running VM uses a GPU.'
            } else {
                try {
                    $cards = @($hostRows | Where-Object Gpus)
                    $totalCards = ($cards | Measure-Object -Property Gpus -Sum).Sum
                    $maxCards = ($cards | Measure-Object -Property Gpus -Maximum).Maximum
                    if (-not $totalCards) {
                        throw [System.InvalidOperationException]::new('no GPU cards reported on the hosts (gpuList)')
                    }
                    $profiles = @(
                        GetNxoPagedList -Connection $connection -Namespace clustermgmt -Path "/config/clusters/$($cluster.extId)/virtual-gpu-profiles" -PreferVersion $PreferApiVersion |
                            ForEach-Object { [PSCustomObject]@{ Kind = 'vGPU'; Config = $_.virtualGpuConfig; Allocated = GetNxoItemCount -Value $_.allocatedVmExtIds } }
                        GetNxoPagedList -Connection $connection -Namespace clustermgmt -Path "/config/clusters/$($cluster.extId)/physical-gpu-profiles" -PreferVersion $PreferApiVersion |
                            ForEach-Object { [PSCustomObject]@{ Kind = 'Passthrough'; Config = $_.physicalGpuConfig; Allocated = GetNxoItemCount -Value $_.allocatedVmExtIds } }
                    ) | Where-Object { $_.Allocated -gt 0 }
                    $share = $maxCards / $totalCards
                    $short = @()
                    $lines = @()
                    foreach ($gpuProfile in @($profiles)) {
                        $capacity = $gpuProfile.Allocated + [int]$gpuProfile.Config.assignable
                        $capacityN1 = [Math]::Floor($capacity * (1 - $share))
                        $lines += '{0} {1}: {2} in use, capacity {3}, N-1 approx. {4}' -f $gpuProfile.Kind, $gpuProfile.Config.deviceName, $gpuProfile.Allocated, $capacity, $capacityN1
                        if ($gpuProfile.Allocated -gt $capacityN1) { $short += [string]$gpuProfile.Config.deviceName }
                    }
                    $result = if ($short.Count) { 'FAIL' } else { 'PASS' }
                    AddNxoCheck -List $checks -Check 'GPU with N-1' -Result $result -Value "$($gpuVms.Count) GPU VM(s)" -Threshold 'GPU profiles in use fit on N-1' -Detail ("$totalCards card(s), max $maxCards per host. " + ($lines -join '; '))
                } catch {
                    AddNxoCheck -List $checks -Check 'GPU with N-1' -Result WARN -Value "$($gpuVms.Count) GPU VM(s)" -Threshold 'GPU profiles in use fit on N-1' -Detail "GPU capacity could not be determined ($($_.Exception.Message)) - check manually."
                }
            }

            # ===== 9. Non-migratable VMs =====
            $nonMigratable = GetNxoNonMigratableVm -Connection $connection -Cluster $cluster -HostList $hosts -RunningVm $runningVms
            $extra.NonMigratable = @($nonMigratable.Vm)
            $agentVms = @($runningVms | Where-Object isAgentVm).Count
            if (@($nonMigratable.Vm).Count) {
                $list = (@($nonMigratable.Vm) | Select-Object -First 5 | ForEach-Object { '{0} ({1})' -f $_.VM, $_.Reason }) -join ', '
                AddNxoCheck -List $checks -Check 'Non-migratable VMs' -Result WARN -Value "$(@($nonMigratable.Vm).Count) VM(s)" -Threshold 'None' -Detail "Must be shut down or handled manually during maintenance. Source: $($nonMigratable.Source). $list"
            } else {
                $detail = "Source: $($nonMigratable.Source)."
                if ($agentVms) { $detail += " $agentVms agent VM(s) - these are powered off automatically with the host." }
                AddNxoCheck -List $checks -Check 'Non-migratable VMs' -Result PASS -Value 'None' -Threshold 'None' -Detail $detail
            }

            # ===== 10. NCC =====
            if ($SkipNcc) {
                AddNxoCheck -List $checks -Check 'NCC health checks' -Result SKIPPED -Value '-' -Threshold 'Run before upgrade' -Detail 'Skipped (-SkipNcc).'
            } else {
                $nccResult = GetNxoNccCheckResult -Connection $connection -Cluster $cluster -NccTask $nccTasks[$cluster.extId] -TimeoutMinutes $NccTimeoutMinutes -Recipient $nccState.Recipients -CheckCache $checkCache
                $extra.Ncc = $nccResult.Ncc
                AddNxoCheck -List $checks -Check 'NCC health checks' -Result $nccResult.Result -Value $nccResult.Value -Threshold $nccResult.Threshold -Detail $nccResult.Detail
            }

            # ===== 11. Open alerts (read after NCC so new findings are included) =====
            try {
                try {
                    $alerts = @(GetNxoPagedList -Connection $connection -Namespace monitoring -Path '/serviceability/alerts' -Query ('$filter={0}' -f [uri]::EscapeDataString('isResolved eq false')))
                } catch {
                    Write-Verbose "Alert filter rejected, reading all alerts: $($_.Exception.Message)"
                    $alerts = @(GetNxoPagedList -Connection $connection -Namespace monitoring -Path '/serviceability/alerts' | Where-Object { -not $_.isResolved })
                }
                $alerts = @($alerts | Where-Object {
                        ($_.clusterUUID -eq $cluster.extId -or $_.originatingClusterUUID -eq $cluster.extId) -and $_.severity -in @('CRITICAL', 'WARNING')
                    } | Sort-Object -Property @{ Expression = { if ($_.severity -eq 'CRITICAL') { 0 } else { 1 } } }, creationTime | ForEach-Object {
                        [PSCustomObject]@{
                            Severity       = $_.severity
                            Title          = ExpandNxoAlertText -Text $_.title -Parameters $_.parameters
                            Message        = ExpandNxoAlertText -Text $_.message -Parameters $_.parameters
                            Created        = ConvertToNxoLocalTime -Timestamp $_.creationTime
                            Acknowledged   = [bool]$_.isAcknowledged
                            AcknowledgedBy = $_.acknowledgedByUsername
                        }
                    })
                if ($extra.Ncc) {
                    $nccStart = $extra.Ncc.Started.AddMinutes(-1)
                    foreach ($alert in $alerts) {
                        if ($alert.Created -and $alert.Created -ge $nccStart) { $alert.Message = "$($alert.Message) [raised during NCC run]" }
                    }
                    $extra.Ncc.NewAlerts = @($alerts | Where-Object { $_.Created -and $_.Created -ge $nccStart })
                }
                $open = @($alerts | Where-Object { -not $_.Acknowledged })
                $extra.AckAlerts = @($alerts | Where-Object Acknowledged)

                # One finding (and one justification) per alert title and severity
                foreach ($group in ($open | Group-Object -Property Severity, Title)) {
                    $first = $group.Group[0]
                    $times = if ($group.Count -gt 1) { " ($($group.Count)x)" } else { '' }
                    $messages = @($group.Group | Sort-Object -Property Created | ForEach-Object { '{0} (raised {1:yyyy-MM-dd HH:mm})' -f $_.Message, $_.Created } | Select-Object -Unique)
                    $more = if ($messages.Count -gt 5) { " ... and $($messages.Count - 5) more" } else { '' }
                    AddNxoCheck -List $checks -Check "Alert: $($first.Title)$times" -Result WARN -Value $first.Severity -Threshold 'No open Critical/Warning alerts' -Detail ((($messages | Select-Object -First 5) -join ' | ') + $more)
                }
                if (-not $open.Count) {
                    AddNxoCheck -List $checks -Check 'Open alerts' -Result PASS -Value '0 unacknowledged' -Threshold 'No open Critical/Warning alerts' -Detail "$(@($extra.AckAlerts).Count) acknowledged alert(s) listed for information."
                }
            } catch {
                AddNxoCheck -List $checks -Check 'Open alerts' -Result WARN -Value 'n/a' -Threshold 'No open Critical/Warning alerts' -Detail "Alerts could not be read: $($_.Exception.Message) - check Prism manually."
            }

            # ===== Justifications and verdict =====
            ReadNxoJustification -Check $checks.ToArray() -ClusterName $cluster.name -NonInteractive:$NonInteractive

            $verdict = if ($checks.Result -contains 'FAIL') { 'NO-GO' } elseif ($checks.Result -contains 'WARN') { 'GO WITH RESERVATIONS' } else { 'GO' }
            $color = switch ($verdict) { 'GO' { 'Green' } 'NO-GO' { 'Red' } default { 'Yellow' } }
            Write-Host "  $($cluster.name): $verdict" -ForegroundColor $color

            $reportParam = @{
                Folder       = $ReportFolder
                PrismCentral = $pc
                Cluster      = $cluster
                Verdict      = $verdict
                Check        = $checks.ToArray()
                Extra        = $extra
                Engineer     = $Engineer
                StartTime    = $startTime
                EndTime      = $endTime
            }
            if ($ChangeId) { $reportParam.ChangeId = $ChangeId }
            $reportPath = ExportNxoUpgradeReport @reportParam
            Write-Host "  Report: $reportPath" -ForegroundColor Green

            foreach ($check in $checks) {
                $row = [PSCustomObject][ordered]@{
                    PrismCentral  = $pc
                    Cluster       = $cluster.name
                    Verdict       = $verdict
                    Check         = $check.Check
                    Result        = $check.Result
                    Value         = $check.Value
                    Threshold     = $check.Threshold
                    Detail        = $check.Detail
                    Justification = $check.Justification
                    ReportPath    = $reportPath
                }
                $row.PSObject.TypeNames.Insert(0, 'PSNutanixOps.UpgradeReadinessCheck')
                $results.Add($row)
            }
        }
    }

    Write-Verbose "Completed $($MyInvocation.MyCommand)"
    return $results.ToArray()
}
