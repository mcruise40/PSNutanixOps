function GetNxoClusterList {
    <#
    .SYNOPSIS
        Returns the AOS clusters registered to a Prism Central.

    .DESCRIPTION
        Internal helper. Reads clustermgmt config/clusters and removes the Prism Central
        self-registration (config.clusterFunction contains PRISM_CENTRAL), which the host and
        stats APIs reject. Clusters without a readable clusterFunction are treated as AOS
        clusters. With -ClusterName only the named clusters are returned (case-insensitive).

    .PARAMETER Connection
        Connection object from the connection store.

    .PARAMETER ClusterName
        Optional Prism Element cluster name(s) to keep.

    .PARAMETER PreferVersion
        Passed to the API call.

    .EXAMPLE
        GetNxoClusterList -Connection $connection -ClusterName 'NTNX-CL01'

    .OUTPUTS
        PSCustomObject (clustermgmt cluster)

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

        [Parameter()]
        [string[]]
        $ClusterName,

        [Parameter()]
        [ValidatePattern('^v4\.\d+$')]
        [string]
        $PreferVersion
    )

    $listParam = @{ Connection = $Connection; Namespace = 'clustermgmt'; Path = '/config/clusters' }
    if ($PreferVersion) { $listParam.PreferVersion = $PreferVersion }

    $clusters = @(GetNxoPagedList @listParam | Where-Object { @($_.config.clusterFunction) -notcontains 'PRISM_CENTRAL' })

    if ($ClusterName) {
        $clusters = @($clusters | Where-Object { $ClusterName -contains $_.name })
        foreach ($name in $ClusterName) {
            if (-not ($clusters | Where-Object { $_.name -eq $name })) {
                Write-Verbose "Cluster '$name' not found on $($Connection.Server)."
            }
        }
    }

    # Emitted item by item; callers wrap the result in @() when they need an array.
    foreach ($cluster in $clusters) { $cluster }
}
