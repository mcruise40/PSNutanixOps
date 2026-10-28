function Remove-NxoRecoveryPoint {
    <#
    .SYNOPSIS
        Deletes recovery points by their extId.

    .DESCRIPTION
        Deletes one or more recovery points via the dataprotection API and waits for each task.
        Deletion is irreversible: ConfirmImpact is High, so PowerShell asks for each recovery
        point unless -Confirm:$false is given. -WhatIf shows what would be deleted.

        The recovery point is looked up first to show its name and VM(s) in the prompt. Without
        -Server it is searched on every connected Prism Central; with pipeline input from
        Get-NxoRecoveryPoint the Prism Central is taken from the PrismCentral property.

    .PARAMETER ExtId
        Recovery point extId(s). Accepts pipeline input by property name (ExtId).

    .PARAMETER Server
        Prism Central that holds the recovery point. Accepts pipeline input by property name
        (PrismCentral). Default: search all connections.

    .PARAMETER TimeoutSeconds
        Maximum time to wait for each deletion task. Default: 600.

    .EXAMPLE
        Remove-NxoRecoveryPoint -ExtId 1ffff90f-f11f-4613-88d6-ceadac77f16d -WhatIf

        Shows which recovery point would be deleted.

    .EXAMPLE
        Get-NxoRecoveryPoint -VmName VM01 | Where-Object Expiry -lt (Get-Date) | Remove-NxoRecoveryPoint -Confirm:$false

        Deletes the expired recovery points of VM01 without prompting.

    .INPUTS
        System.String

    .OUTPUTS
        PSCustomObject (PSNutanixOps.RecoveryPointResult)

    .LINK
        Get-NxoRecoveryPoint
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('RecoveryPointExtIds', 'RecoveryPointExtId')]
        [string[]]
        $ExtId,

        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('PrismCentral')]
        [string]
        $Server,

        [Parameter()]
        [ValidateRange(30, 7200)]
        [int]
        $TimeoutSeconds = 600
    )

    begin {
        Write-Verbose "Starting $($MyInvocation.MyCommand)"
        $vmNameCache = @{}
    }

    process {
        $connections = @(GetNxoTargetConnection -Server $Server)

        foreach ($id in $ExtId) {
            # Find the recovery point (and the Prism Central that holds it) for a clear prompt.
            $owner = $null
            $recoveryPoint = $null
            foreach ($connection in $connections) {
                try {
                    $recoveryPoint = (InvokeNxoApi -Connection $connection -Namespace dataprotection -Path "/config/recovery-points/$id").data
                    $owner = $connection
                    break
                } catch {
                    Write-Verbose "Recovery point $id not readable on $($connection.Server): $($_.Exception.Message)"
                }
            }
            if ($null -eq $owner) {
                if ($connections.Count -ne 1) {
                    $exception = [System.Management.Automation.ItemNotFoundException]::new("Recovery point '$id' was not found on any connected Prism Central.")
                    $PSCmdlet.WriteError([System.Management.Automation.ErrorRecord]::new($exception, 'NxoRecoveryPointNotFound', [System.Management.Automation.ErrorCategory]::ObjectNotFound, $id))
                    continue
                }
                # Single Prism Central: try the deletion anyway, the API reports the real reason.
                $owner = $connections[0]
            }
            $pc = $owner.Server

            $vmNames = @()
            if ($recoveryPoint) {
                if (-not $vmNameCache.ContainsKey($pc)) {
                    $map = @{}
                    try {
                        foreach ($vm in (GetNxoPagedList -Connection $owner -Namespace vmm -Path '/ahv/config/vms')) { $map[$vm.extId] = $vm.name }
                    } catch {
                        Write-Verbose "VM names on $pc not readable: $($_.Exception.Message)"
                    }
                    $vmNameCache[$pc] = $map
                }
                $vmNames = @(@($recoveryPoint.vmRecoveryPoints).vmExtId | Where-Object { $_ } | ForEach-Object { ResolveNxoName -Map $vmNameCache[$pc] -ExtId $_ })
            }

            $label = if ($recoveryPoint.name) { "'$($recoveryPoint.name)' ($id)" } else { $id }
            if ($vmNames.Count) { $label += " [VM: $($vmNames -join ', ')]" }

            if (-not $PSCmdlet.ShouldProcess("$label on $pc", 'Permanently delete recovery point')) {
                continue
            }

            $status = 'FAILED'
            $taskExtId = $null
            $message = $null
            try {
                $response = InvokeNxoApi -Connection $owner -Namespace dataprotection -Method DELETE -Path "/config/recovery-points/$id"
                $taskExtId = $response.data.extId
                if (-not $taskExtId) {
                    throw [System.InvalidOperationException]::new('No task extId returned by Prism Central.')
                }
                $task = WaitNxoTask -Connection $owner -TaskExtId $taskExtId -TimeoutSeconds $TimeoutSeconds -Activity "Deleting recovery point $id"
                $status = [string]$task.status
                if ($status -in @('QUEUED', 'RUNNING')) {
                    $status = 'TIMEOUT'
                    $message = "Task not finished after $TimeoutSeconds s; it may still be running."
                } elseif ($status -ne 'SUCCEEDED') {
                    $message = (@($task.errorMessages | ForEach-Object { $_.message } | Where-Object { $_ }) -join '; ')
                }
            } catch {
                Write-Verbose "$($MyInvocation.MyCommand) failed for '$id': $_"
                $message = $_.Exception.Message
            }

            if ($status -ne 'SUCCEEDED') {
                Write-Warning "Deletion of recovery point $label on $($pc): $status $message"
            }
            $row = [PSCustomObject][ordered]@{
                PrismCentral      = $pc
                ExtId             = $id
                RecoveryPointName = $recoveryPoint.name
                VMs               = $vmNames -join ', '
                Status            = $status
                Success           = $status -eq 'SUCCEEDED'
                TaskExtId         = $taskExtId
                Message           = $message
            }
            $row.PSObject.TypeNames.Insert(0, 'PSNutanixOps.RecoveryPointResult')
            $row
        }
    }

    end {
        Write-Verbose "Completed $($MyInvocation.MyCommand)"
    }
}
