function GetNxoNonMigratableVm {
    <#
    .SYNOPSIS
        Returns the VMs of a cluster that cannot be live-migrated.

    .DESCRIPTION
        Internal helper for Test-NxoUpgradeReadiness. Runs the AOS action
        compute-non-migratable-vms (covers affinity rules) and reads its result. The result
        extId is not documented explicitly; it is one of the task's affected entities (besides
        the cluster and the hosts) or in its completion details.

        Because the AOS result was observed to come back empty on some runs, the running VMs
        are also checked by their properties (isLiveMigrateCapable, GPU passthrough, PCIe
        devices). VMs found only that way are marked as such. If the action is not usable,
        only the properties are used and affinity rules are not covered.

    .PARAMETER Connection
        Connection object from the connection store.

    .PARAMETER Cluster
        The cluster (clustermgmt cluster object).

    .PARAMETER HostList
        The hosts of the cluster.

    .PARAMETER RunningVm
        The running VMs of the cluster.

    .EXAMPLE
        GetNxoNonMigratableVm -Connection $c -Cluster $cl -HostList $hosts -RunningVm $onVms

    .OUTPUTS
        PSCustomObject with Vm (list of VM, Reason, Host) and Source

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
        [ValidateNotNull()]
        [PSCustomObject]
        $Cluster,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $HostList,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $RunningVm
    )

    $fromAos = $null
    try {
        $body = @{ hosts = @($HostList.extId) }
        $response = InvokeNxoApi -Connection $Connection -Namespace clustermgmt -Method POST -Path "/config/clusters/$($Cluster.extId)/`$actions/compute-non-migratable-vms" -Body $body
        $task = WaitNxoTask -Connection $Connection -TaskExtId $response.data.extId -TimeoutSeconds 300
        if ($task.status -ne 'SUCCEEDED') {
            throw [System.InvalidOperationException]::new("task status $($task.status)")
        }

        $known = @($Cluster.extId) + @($HostList.extId)
        $candidates = @(@($task.completionDetails.value) + @($task.entitiesAffected.extId) |
                Where-Object { $_ -match '^[0-9a-f]{8}-[0-9a-f]{4}-' -and $known -notcontains $_ } | Select-Object -Unique)
        foreach ($id in $candidates) {
            try {
                $result = InvokeNxoApi -Connection $Connection -Namespace clustermgmt -Path "/config/clusters/$($Cluster.extId)/non-migratable-vms-result/$id"
                $fromAos = @($result.data.vms | Where-Object { $null -ne $_ -and $_.vmName } | ForEach-Object {
                        [PSCustomObject]@{ VM = $_.vmName; Reason = $_.nonMigratableVmReason; Host = $_.hostIp.ipv4.value }
                    })
                break
            } catch {
                Write-Verbose "Result $id not readable: $($_.Exception.Message)"
            }
        }
        if ($null -eq $fromAos) {
            throw [System.InvalidOperationException]::new('result not found in task details')
        }
    } catch {
        Write-Verbose "compute-non-migratable-vms not usable on $($Cluster.name): $($_.Exception.Message) - using VM properties only"
        $fromAos = $null
    }

    $byProperties = @(foreach ($vm in $RunningVm) {
            $reasons = @()
            if ($vm.isLiveMigrateCapable -eq $false) { $reasons += 'not live-migrate capable' }
            if (@($vm.gpus | Where-Object { $_.mode -like 'PASSTHROUGH*' }).Count) { $reasons += 'GPU passthrough' }
            if ((GetNxoItemCount -Value $vm.pcieDevices) -gt 0) { $reasons += 'PCIe device' }
            if ($reasons.Count) {
                $hostName = ($HostList | Where-Object { $_.extId -eq $vm.host.extId } | Select-Object -First 1).hostName
                [PSCustomObject]@{ VM = $vm.name; Reason = $reasons -join ', '; Host = if ($hostName) { $hostName } else { $vm.host.extId } }
            }
        })

    if ($null -eq $fromAos) {
        return [PSCustomObject]@{
            Vm     = $byProperties
            Source = 'VM properties (isLiveMigrateCapable, GPU passthrough, PCIe devices) - affinity rules not covered'
        }
    }

    $missing = @($byProperties | Where-Object { @($fromAos.VM) -notcontains $_.VM })
    foreach ($entry in $missing) { $entry.Reason = "$($entry.Reason) - VM property only, not in AOS result" }

    return [PSCustomObject]@{
        Vm     = @($fromAos) + $missing
        Source = 'AOS compute-non-migratable-vms, cross-checked with VM properties'
    }
}
