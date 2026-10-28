function GetNxoNameMap {
    <#
    .SYNOPSIS
        Builds an extId -> display name lookup table from a v4 list endpoint.

    .DESCRIPTION
        Internal helper for readable output (cluster, host, category and subnet names instead
        of extIds). Best effort: if the list cannot be read, a warning is written and an empty
        table is returned, so the caller shows extIds instead.

    .PARAMETER Connection
        Connection object from the connection store.

    .PARAMETER Kind
        Which lookup to build: Cluster, Host, Category or Subnet.

    .EXAMPLE
        $clusterNames = GetNxoNameMap -Connection $connection -Kind Cluster

    .OUTPUTS
        System.Collections.Hashtable

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]
        $Connection,

        [Parameter(Mandatory)]
        [ValidateSet('Cluster', 'Host', 'Category', 'Subnet')]
        [string]
        $Kind
    )

    $map = @{}
    try {
        switch ($Kind) {
            'Cluster' {
                foreach ($item in (GetNxoPagedList -Connection $Connection -Namespace clustermgmt -Path '/config/clusters')) {
                    if ($item.extId) { $map[$item.extId] = $item.name }
                }
            }
            'Host' {
                foreach ($item in (GetNxoPagedList -Connection $Connection -Namespace clustermgmt -Path '/config/hosts')) {
                    if ($item.extId) { $map[$item.extId] = $item.hostName }
                }
            }
            'Category' {
                foreach ($item in (GetNxoPagedList -Connection $Connection -Namespace prism -Path '/config/categories')) {
                    if ($item.extId) { $map[$item.extId] = '{0}:{1}' -f $item.key, $item.value }
                }
            }
            'Subnet' {
                foreach ($item in (GetNxoPagedList -Connection $Connection -Namespace networking -Path '/config/subnets')) {
                    if ($item.extId) { $map[$item.extId] = $item.name }
                }
            }
        }
    } catch {
        Write-Verbose "$($MyInvocation.MyCommand) failed for '$Kind' on $($Connection.Server): $_"
        Write-Warning ('Could not resolve {0} names on {1} - showing extIds instead.' -f $Kind.ToLowerInvariant(), $Connection.Server)
        return @{}
    }

    return $map
}
