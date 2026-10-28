function GetNxoPagedList {
    <#
    .SYNOPSIS
        Reads all pages of a Nutanix v4 list endpoint.

    .DESCRIPTION
        Internal helper. v4 list calls are paged with $page (zero-based) and $limit (max. 100).
        $offset is silently ignored by the API and would cause an endless loop, so it is never
        used. Reading stops when a page is not full or when metadata.totalAvailableResults is
        reached.

    .PARAMETER Connection
        Connection object from the connection store.

    .PARAMETER Namespace
        API namespace, e.g. vmm.

    .PARAMETER Path
        List path below the revision, without query, e.g. /ahv/config/vms.

    .PARAMETER Query
        Additional OData query without leading ?, e.g. $filter=... (already URL-encoded).

    .PARAMETER PageSize
        Items per page. Default and maximum: 100.

    .PARAMETER Activity
        Optional text for Write-Progress.

    .PARAMETER PreferVersion
        Passed to InvokeNxoApi.

    .EXAMPLE
        GetNxoPagedList -Connection $connection -Namespace vmm -Path '/ahv/config/vms'

    .OUTPUTS
        PSCustomObject (one per list item)

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

        [Parameter(Mandatory)]
        [ValidatePattern('^[a-z]+$')]
        [string]
        $Namespace,

        [Parameter(Mandatory)]
        [ValidatePattern('^/[^?]*$')]
        [string]
        $Path,

        [Parameter()]
        [string]
        $Query,

        [Parameter()]
        [ValidateRange(1, 100)]
        [int]
        $PageSize = 100,

        [Parameter()]
        [string]
        $Activity,

        [Parameter()]
        [ValidatePattern('^v4\.\d+$')]
        [string]
        $PreferVersion
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $apiParam = @{ Connection = $Connection; Namespace = $Namespace }
    if ($PreferVersion) { $apiParam.PreferVersion = $PreferVersion }

    for ($page = 0; $page -lt 100000; $page++) {
        $paging = '$page={0}&$limit={1}' -f $page, $PageSize
        $fullQuery = if ($Query) { '{0}&{1}' -f $Query, $paging } else { $paging }
        $response = InvokeNxoApi @apiParam -Path ('{0}?{1}' -f $Path, $fullQuery)

        $data = @($response.data | Where-Object { $null -ne $_ })
        foreach ($entry in $data) { $items.Add($entry) }

        $total = $response.metadata.totalAvailableResults
        if ($Activity) {
            $status = if ($total) { '{0} of {1}' -f $items.Count, $total } else { [string]$items.Count }
            Write-Progress -Activity $Activity -Status $status
        }
        if ($data.Count -lt $PageSize -or ($total -and $items.Count -ge $total)) { break }
    }

    if ($Activity) { Write-Progress -Activity $Activity -Completed }

    return $items.ToArray()
}
