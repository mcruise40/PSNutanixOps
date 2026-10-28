function GetNxoEntityState {
    <#
    .SYNOPSIS
        Checks a VM or volume group on every Prism Central of a cleanup run.

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup. An entity only counts as Missing if
        every Prism Central answers "not found":
        - VM: looked up as AHV VM, and as ESXi VM on Prism Centrals whose ESXi list could be
          read. A non-AHV VM on a Prism Central without readable ESXi list is Unverified.
        - Volume group: a Prism Central whose volume group list could not be read is not
          trusted (its 404 may mean the API is missing, not the volume group).
        Any Exists wins; otherwise any Unverified wins; otherwise Missing.

    .PARAMETER Pc
        The Prism Central entries of the run (Connection, EsxiListOk, VgListOk).

    .PARAMETER Kind
        Vm or VolumeGroup.

    .PARAMETER ExtId
        External ID of the entity.

    .PARAMETER HypervisorType
        Hypervisor type of the VM as stored in the recovery point (AHV, ESX, ...).

    .EXAMPLE
        GetNxoEntityState -Pc $pcs -Kind Vm -ExtId $id -HypervisorType AHV

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
        [object[]]
        $Pc,

        [Parameter(Mandatory)]
        [ValidateSet('Vm', 'VolumeGroup')]
        [string]
        $Kind,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ExtId,

        [Parameter()]
        [string]
        $HypervisorType
    )

    $answers = foreach ($entry in $Pc) {
        if ($Kind -eq 'Vm') {
            GetNxoLookupState -Connection $entry.Connection -Namespace vmm -Path "/ahv/config/vms/$ExtId"
            if ($entry.EsxiListOk) {
                GetNxoLookupState -Connection $entry.Connection -Namespace vmm -Path "/esxi/config/vms/$ExtId"
            } elseif ($HypervisorType -and $HypervisorType -ne 'AHV') {
                'Unverified'
            }
        } elseif ($entry.VgListOk) {
            GetNxoLookupState -Connection $entry.Connection -Namespace volumes -Path "/config/volume-groups/$ExtId"
        } else {
            'Unverified'
        }
    }
    $answers = @($answers)

    if ($answers -contains 'Exists') { return 'Exists' }
    if ($answers -contains 'Unverified') { return 'Unverified' }

    return 'Missing'
}
