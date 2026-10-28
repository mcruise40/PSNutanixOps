function Get-NxoRecoveryPoint {
    <#
    .SYNOPSIS
        Lists recovery points of the connected Prism Central instances.

    .DESCRIPTION
        Returns the recovery points (dataprotection API), optionally only those of specific VMs
        (by name) or of all VMs that carry a category. VM extIds are resolved to names. The
        output can be piped to Remove-NxoRecoveryPoint.

        Recovery points without VM (e.g. volume-group-only) are listed without VM name.

    .PARAMETER Server
        Only query these connected Prism Central instance(s). Default: all connections.

    .PARAMETER VmName
        Only recovery points that contain these VM(s). Case-insensitive, wildcards allowed.

    .PARAMETER CategoryKey
        Category key (e.g. Patching) to select VMs; use together with -CategoryValue.

    .PARAMETER CategoryValue
        Category value (e.g. Group01) used together with -CategoryKey.

    .PARAMETER Raw
        Return the raw API objects instead of the simplified view (to inspect field names).

    .EXAMPLE
        Get-NxoRecoveryPoint

        Lists all recovery points.

    .EXAMPLE
        Get-NxoRecoveryPoint -VmName VM01, VM02

        Lists the recovery points that contain VM01 and/or VM02.

    .EXAMPLE
        Get-NxoRecoveryPoint -CategoryKey Patching -CategoryValue Group01 | Where-Object Name -like 'PrePatch*' | Remove-NxoRecoveryPoint

        Deletes the PrePatch recovery points of all VMs in category Patching:Group01 (asks per
        recovery point).

    .INPUTS
        None

    .OUTPUTS
        PSCustomObject (PSNutanixOps.RecoveryPoint)

    .NOTES
        creationTime and expirationTime are not confirmed against an official field list for
        this endpoint; missing fields show up empty. Use -Raw to inspect the response.

    .LINK
        New-NxoRecoveryPoint

    .LINK
        Remove-NxoRecoveryPoint
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
        [switch]
        $Raw
    )

    Write-Verbose "Starting $($MyInvocation.MyCommand)"
    $connections = GetNxoTargetConnection -Server $Server
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    foreach ($connection in $connections) {
        $pc = $connection.Server
        try {
            $vms = @(GetNxoPagedList -Connection $connection -Namespace vmm -Path '/ahv/config/vms' -Activity "$($pc): reading VMs")
            $recoveryPoints = @(GetNxoPagedList -Connection $connection -Namespace dataprotection -Path '/config/recovery-points' -Activity "$($pc): reading recovery points")
        } catch {
            Write-Verbose "$($MyInvocation.MyCommand) failed for '$pc': $_"
            Write-Warning "Skipping Prism Central $pc - $($_.Exception.Message)"
            continue
        }

        $filterIds = $null
        if ($PSCmdlet.ParameterSetName -eq 'ByName') {
            $filterIds = @(SelectNxoVm -Vm $vms -VmName $VmName | ForEach-Object { $_.extId })
        } elseif ($PSCmdlet.ParameterSetName -eq 'ByCategory') {
            $categoryExtId = ResolveNxoCategoryExtId -Connection $connection -Key $CategoryKey -Value $CategoryValue
            if (-not $categoryExtId) {
                Write-Warning "No category '$($CategoryKey):$CategoryValue' on $pc - skipping this Prism Central."
                continue
            }
            $filterIds = @(SelectNxoVm -Vm $vms -CategoryExtId $categoryExtId | ForEach-Object { $_.extId })
        }
        if ($null -ne $filterIds) {
            if (-not $filterIds.Count) {
                Write-Verbose "No matching VMs on $pc."
                continue
            }
            $recoveryPoints = @($recoveryPoints | Where-Object {
                    @(@($_.vmRecoveryPoints).vmExtId | Where-Object { $filterIds -contains $_ }).Count -gt 0
                })
        }

        if ($Raw) {
            foreach ($recoveryPoint in $recoveryPoints) { $results.Add($recoveryPoint) }
            continue
        }

        $vmNames = @{}
        foreach ($vm in $vms) { if ($vm.extId) { $vmNames[$vm.extId] = $vm.name } }

        foreach ($recoveryPoint in $recoveryPoints) {
            $names = @(@($recoveryPoint.vmRecoveryPoints).vmExtId | Where-Object { $_ } | ForEach-Object { ResolveNxoName -Map $vmNames -ExtId $_ })
            $row = [PSCustomObject][ordered]@{
                PrismCentral = $pc
                Name         = $recoveryPoint.name
                ExtId        = $recoveryPoint.extId
                Status       = $recoveryPoint.status
                Type         = $recoveryPoint.recoveryPointType
                VMs          = $names -join ', '
                Created      = ConvertToNxoLocalTime -Timestamp $recoveryPoint.creationTime
                Expiry       = ConvertToNxoLocalTime -Timestamp $recoveryPoint.expirationTime
            }
            $row.PSObject.TypeNames.Insert(0, 'PSNutanixOps.RecoveryPoint')
            $results.Add($row)
        }
    }

    Write-Verbose "Completed $($MyInvocation.MyCommand)"
    if ($Raw) { return $results.ToArray() }

    return $results | Sort-Object -Property Created -Descending
}
