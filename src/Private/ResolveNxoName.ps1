function ResolveNxoName {
    <#
    .SYNOPSIS
        Looks up the display name of an extId, falling back to the extId itself.

    .DESCRIPTION
        Internal helper used together with GetNxoNameMap. Returns $null for an empty extId.

    .PARAMETER Map
        Lookup table extId -> name.

    .PARAMETER ExtId
        The external ID to resolve.

    .EXAMPLE
        ResolveNxoName -Map $clusterNames -ExtId $vm.cluster.extId

    .OUTPUTS
        System.String or $null

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [hashtable]
        $Map,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]
        $ExtId
    )

    if ([string]::IsNullOrEmpty($ExtId)) { return $null }
    if ($null -ne $Map -and $Map.ContainsKey($ExtId) -and $Map[$ExtId]) { return [string]$Map[$ExtId] }

    return $ExtId
}
