function GetNxoRecoveryPointSize {
    <#
    .SYNOPSIS
        Returns the reclaimable space of a recovery point in bytes, or $null.

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup. Uses totalExclusiveUsageBytes (API
        v4.2 and later), documented as the space that could be reclaimed after deleting the
        recovery point; falls back to the sum over its VM and volume group recovery points.

    .PARAMETER RecoveryPoint
        dataprotection recovery point object.

    .EXAMPLE
        GetNxoRecoveryPointSize -RecoveryPoint $rp

    .OUTPUTS
        System.Int64 or $null

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([long])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]
        $RecoveryPoint
    )

    if ($null -eq $RecoveryPoint) { return $null }
    if ($null -ne $RecoveryPoint.totalExclusiveUsageBytes) { return [long]$RecoveryPoint.totalExclusiveUsageBytes }

    $parts = @(@($RecoveryPoint.vmRecoveryPoints) + @($RecoveryPoint.volumeGroupRecoveryPoints) |
            Where-Object { $_ -and $null -ne $_.totalExclusiveUsageBytes })
    if ($parts.Count) { return [long]($parts | Measure-Object -Property totalExclusiveUsageBytes -Sum).Sum }

    return $null
}
