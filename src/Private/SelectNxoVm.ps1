function SelectNxoVm {
    <#
    .SYNOPSIS
        Filters a VM list by name pattern(s) or by category.

    .DESCRIPTION
        Internal helper shared by the recovery point commands. With -VmName every VM whose name
        matches one of the patterns (case-insensitive, wildcards allowed) is returned. With
        -CategoryExtId every VM that carries this category is returned. Without filter all
        VMs are returned.

    .PARAMETER Vm
        VM list (vmm.v4.ahv.config.Vm objects).

    .PARAMETER VmName
        Name pattern(s).

    .PARAMETER CategoryExtId
        External ID of a category.

    .EXAMPLE
        SelectNxoVm -Vm $vms -VmName 'SQL*'

    .OUTPUTS
        PSCustomObject (VM)

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]
        $Vm,

        [Parameter()]
        [string[]]
        $VmName,

        [Parameter()]
        [string]
        $CategoryExtId
    )

    foreach ($candidate in @($Vm | Where-Object { $null -ne $_ })) {
        if ($VmName) {
            $name = [string]$candidate.name
            if (-not @($VmName | Where-Object { $name -like $_ }).Count) { continue }
        }
        if ($CategoryExtId -and @($candidate.categories).extId -notcontains $CategoryExtId) { continue }
        $candidate
    }
}
