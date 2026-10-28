function ResolveNxoDeletedVmName {
    <#
    .SYNOPSIS
        Reads the name of a deleted VM from the VM configuration stored in a recovery point.

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup. The vmm vm-recovery-points API
        still has the configuration (and the name) of a VM that no longer exists. Tries the
        VM recovery point extId first, then the recovery point extId. If both fail, returns a
        placeholder with the short VM ID.

    .PARAMETER Connection
        Connection object from the connection store.

    .PARAMETER RecoveryPoint
        dataprotection recovery point object.

    .PARAMETER VmExtId
        External ID of the deleted VM.

    .EXAMPLE
        ResolveNxoDeletedVmName -Connection $c -RecoveryPoint $rp -VmExtId $id

    .OUTPUTS
        System.String

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]
        $Connection,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]
        $RecoveryPoint,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $VmExtId
    )

    $vmRecoveryPoint = @($RecoveryPoint.vmRecoveryPoints | Where-Object { $_ -and $_.vmExtId -eq $VmExtId })[0]
    foreach ($id in (@($vmRecoveryPoint.extId, $RecoveryPoint.extId) | Where-Object { $_ } | Select-Object -Unique)) {
        try {
            $name = (InvokeNxoApi -Connection $Connection -Namespace vmm -Path "/ahv/config/vm-recovery-points/$id").data.vm.name
            if ($name) { return [string]$name }
        } catch {
            Write-Verbose "No VM name from recovery point ${id}: $($_.Exception.Message)"
        }
    }

    return '(name unknown, VM id {0})' -f (GetNxoShortId -Id $VmExtId)
}
