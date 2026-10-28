function New-NxoRecoveryPoint {
    <#
    .SYNOPSIS
        Creates on-demand recovery points for AHV VMs, one per VM.

    .DESCRIPTION
        Creates one recovery point per target VM via the dataprotection API and waits for each
        task. Target VMs are selected by name or by a category key/value pair and are looked
        up on every connected Prism Central (or the ones named with -Server).

        Always one request per VM, for crash- and app-consistent recovery points alike: this
        avoids the API's limit of one VM per app-consistent request (error DP-10100). A failure
        or timeout on one VM does not stop the others.

        App-consistent recovery points need NGT in the guest (VSS on Windows, pre_freeze /
        post_thaw scripts on Linux); without them Nutanix silently falls back to
        crash-consistent.

    .PARAMETER Server
        Only use these connected Prism Central instance(s). Default: all connections.

    .PARAMETER VmName
        VM name(s). Case-insensitive, wildcards allowed. Accepts pipeline input by property
        name (VM, VmName), e.g. from Get-NxoVmInventory.

    .PARAMETER CategoryKey
        Category key (e.g. Patching) to select VMs; use together with -CategoryValue.

    .PARAMETER CategoryValue
        Category value (e.g. Group1) used together with -CategoryKey.

    .PARAMETER RecoveryPointName
        Name of the recovery points (the same for every VM). Default: OnDemand-<timestamp>.

    .PARAMETER RetentionDays
        Days until the recovery points expire. Default: 1.

    .PARAMETER TimeoutSeconds
        Maximum time to wait for each creation task. Default: 600.

    .PARAMETER AppConsistent
        Request application-consistent recovery points (default: crash-consistent).

    .PARAMETER ProjectExtId
        Optional project extId, relevant in project-scoped / multi-tenant setups.

    .EXAMPLE
        New-NxoRecoveryPoint -VmName VM01 -WhatIf

        Shows which VM would get a recovery point, without creating anything.

    .EXAMPLE
        New-NxoRecoveryPoint -CategoryKey Patching -CategoryValue Group1 -RecoveryPointName PrePatch -RetentionDays 3

        One recovery point named PrePatch for each VM in category Patching:Group1, kept 3 days.

    .EXAMPLE
        Get-NxoVmInventory -ClusterName NTNX-CL01 -ExcludePoweredOff | New-NxoRecoveryPoint -AppConsistent

        App-consistent recovery points for all running VMs of one cluster.

    .INPUTS
        System.String

    .OUTPUTS
        PSCustomObject (PSNutanixOps.RecoveryPointResult)

    .LINK
        Get-NxoRecoveryPoint

    .LINK
        Remove-NxoRecoveryPoint
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', DefaultParameterSetName = 'ByName')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Server,

        [Parameter(Mandatory, ParameterSetName = 'ByName', ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('VM', 'VmNames')]
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
        [string]
        $RecoveryPointName = ('OnDemand-{0:yyyyMMdd-HHmmss}' -f (Get-Date)),

        [Parameter()]
        [ValidateRange(1, 3650)]
        [int]
        $RetentionDays = 1,

        [Parameter()]
        [ValidateRange(30, 7200)]
        [int]
        $TimeoutSeconds = 600,

        [Parameter()]
        [switch]
        $AppConsistent,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ProjectExtId
    )

    begin {
        Write-Verbose "Starting $($MyInvocation.MyCommand)"
        $names = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($name in $VmName) { $names.Add($name) }
    }

    end {
        $connections = GetNxoTargetConnection -Server $Server
        $expiration = ConvertToNxoIsoTime -Date (Get-Date).AddDays($RetentionDays)

        # Resolve the target VMs on every Prism Central (read-only, also runs under -WhatIf).
        $targets = [System.Collections.Generic.List[PSCustomObject]]::new()
        foreach ($connection in $connections) {
            try {
                $vms = @(GetNxoPagedList -Connection $connection -Namespace vmm -Path '/ahv/config/vms')
                if ($PSCmdlet.ParameterSetName -eq 'ByCategory') {
                    $categoryExtId = ResolveNxoCategoryExtId -Connection $connection -Key $CategoryKey -Value $CategoryValue
                    if (-not $categoryExtId) {
                        Write-Verbose "No category '$($CategoryKey):$CategoryValue' on $($connection.Server)."
                        continue
                    }
                    $matched = @(SelectNxoVm -Vm $vms -CategoryExtId $categoryExtId)
                } else {
                    $matched = @(SelectNxoVm -Vm $vms -VmName $names.ToArray())
                }
            } catch {
                Write-Verbose "$($MyInvocation.MyCommand) failed for '$($connection.Server)': $_"
                Write-Warning "Skipping Prism Central $($connection.Server) - $($_.Exception.Message)"
                continue
            }
            foreach ($vm in $matched) {
                $targets.Add([PSCustomObject]@{ Connection = $connection; Name = [string]$vm.name; ExtId = [string]$vm.extId })
            }
        }

        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            foreach ($name in $names) {
                if (-not @($targets | Where-Object { $_.Name -like $name }).Count) {
                    Write-Warning "VM '$name' not found on any connected Prism Central."
                }
            }
        }
        if (-not $targets.Count) {
            Write-Warning 'No matching VMs found - nothing to do.'
            return
        }

        $type = if ($AppConsistent) { 'APPLICATION_CONSISTENT' } else { 'CRASH_CONSISTENT' }
        foreach ($target in $targets) {
            $pc = $target.Connection.Server
            if (-not $PSCmdlet.ShouldProcess("VM $($target.Name) on $pc", "Create recovery point '$RecoveryPointName' (expires $expiration)")) {
                continue
            }

            $vmSpec = @{ vmExtId = $target.ExtId }
            if ($AppConsistent) {
                # 'writers' is omitted: the API rejects an empty array (minItems 1).
                $vmSpec.applicationConsistentProperties = @{
                    '$objectType'          = 'dataprotection.v4.common.VssProperties'
                    backupType             = 'FULL_BACKUP'
                    shouldIncludeWriters   = $false
                    shouldStoreVssMetadata = $false
                }
            }
            $body = @{
                name              = $RecoveryPointName
                expirationTime    = $expiration
                recoveryPointType = $type
                vmRecoveryPoints  = @($vmSpec)
            }
            if ($ProjectExtId) { $body.projectExtId = $ProjectExtId }

            $status = 'FAILED'
            $taskExtId = $null
            $message = $null
            try {
                $response = InvokeNxoApi -Connection $target.Connection -Namespace dataprotection -Method POST -Path '/config/recovery-points' -Body $body
                $taskExtId = $response.data.extId
                if (-not $taskExtId) {
                    throw [System.InvalidOperationException]::new('No task extId returned by Prism Central.')
                }
                $task = WaitNxoTask -Connection $target.Connection -TaskExtId $taskExtId -TimeoutSeconds $TimeoutSeconds -Activity "Recovery point for $($target.Name)"
                $status = [string]$task.status
                if ($status -in @('QUEUED', 'RUNNING')) {
                    $status = 'TIMEOUT'
                    $message = "Task not finished after $TimeoutSeconds s; it may still be running."
                } elseif ($status -ne 'SUCCEEDED') {
                    $message = (@($task.errorMessages | ForEach-Object { $_.message } | Where-Object { $_ }) -join '; ')
                }
            } catch {
                Write-Verbose "$($MyInvocation.MyCommand) failed for VM '$($target.Name)': $_"
                $message = $_.Exception.Message
            }

            if ($status -ne 'SUCCEEDED') {
                Write-Warning "Recovery point for VM '$($target.Name)' on $($pc): $status $message"
            }
            $row = [PSCustomObject][ordered]@{
                PrismCentral      = $pc
                VM                = $target.Name
                RecoveryPointName = $RecoveryPointName
                Type              = $type
                Expires           = ConvertToNxoLocalTime -Timestamp $expiration
                Status            = $status
                Success           = $status -eq 'SUCCEEDED'
                TaskExtId         = $taskExtId
                Message           = $message
            }
            $row.PSObject.TypeNames.Insert(0, 'PSNutanixOps.RecoveryPointResult')
            $row
        }
        Write-Verbose "Completed $($MyInvocation.MyCommand)"
    }
}
