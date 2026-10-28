function InvokeNxoApi {
    <#
    .SYNOPSIS
        Calls a Nutanix v4 API namespace and negotiates the API revision.

    .DESCRIPTION
        Internal helper. Builds /<Namespace>/<revision><Path> and sends it with
        InvokeNxoRestMethod. Not every Prism Central offers every revision in every namespace,
        so the revisions are tried in this order: -PreferVersion, the connection's ApiVersion,
        v4.3, v4.2, v4.1, v4.0. A 404 or 501 answer moves on to the next revision. The first
        revision that works is cached on the connection per namespace and preference, and
        used directly for all later calls. With -Version exactly that revision is used.

    .PARAMETER Connection
        Connection object from the connection store.

    .PARAMETER Namespace
        API namespace, e.g. vmm, clustermgmt, prism, dataprotection, monitoring.

    .PARAMETER Path
        Path below the revision, e.g. /ahv/config/vms?$limit=1.

    .PARAMETER Method
        HTTP method. Default: GET.

    .PARAMETER Body
        Request body; converted to JSON.

    .PARAMETER Version
        Use exactly this revision, without negotiation.

    .PARAMETER PreferVersion
        Revision to try first, e.g. v4.3 for fields that only exist there.

    .EXAMPLE
        InvokeNxoApi -Connection $connection -Namespace vmm -Path '/ahv/config/vms?$limit=1'

    .OUTPUTS
        PSCustomObject (the parsed JSON response)

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
        [ValidatePattern('^/')]
        [string]
        $Path,

        [Parameter()]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
        [string]
        $Method = 'GET',

        [Parameter()]
        [AllowNull()]
        [object]
        $Body,

        [Parameter()]
        [ValidatePattern('^v4\.\d+$')]
        [string]
        $Version,

        [Parameter()]
        [ValidatePattern('^v4\.\d+$')]
        [string]
        $PreferVersion
    )

    $first = if ($PreferVersion) { $PreferVersion } else { $Connection.ApiVersion }
    $cacheKey = '{0}@{1}' -f $Namespace, $first

    if ($Version) {
        $candidates = @($Version)
    } elseif ($Connection.NamespaceVersion.ContainsKey($cacheKey)) {
        $candidates = @($Connection.NamespaceVersion[$cacheKey])
    } else {
        $candidates = @(@($first, $Connection.ApiVersion, 'v4.3', 'v4.2', 'v4.1', 'v4.0') | Where-Object { $_ } | Select-Object -Unique)
    }

    $lastError = $null
    foreach ($revision in $candidates) {
        try {
            $response = InvokeNxoRestMethod -Connection $Connection -Method $Method -Path "/$Namespace/$revision$Path" -Body $Body
            if (-not $Version) {
                $Connection.NamespaceVersion[$cacheKey] = $revision
            }
            return $response
        } catch {
            $lastError = $_
            $statusCode = GetNxoStatusCode -Exception $_.Exception
            if ($candidates.Count -eq 1 -or $statusCode -notin @(404, 501)) {
                throw $_
            }
            Write-Verbose "$($MyInvocation.MyCommand): $Namespace/$revision$Path answered HTTP $statusCode, trying the next revision"
        }
    }

    throw $lastError
}
