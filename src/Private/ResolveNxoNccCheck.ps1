function ResolveNxoNccCheck {
    <#
    .SYNOPSIS
        Resolves an NCC check ID to its title and KB article(s).

    .DESCRIPTION
        Internal helper for Test-NxoUpgradeReadiness. Uses the system-defined alert policies of
        the monitoring API: the ID is tried as extId first, then as policyId filter. Best
        effort and cached per run; unresolved IDs are returned without title.

    .PARAMETER Connection
        Connection object from the connection store.

    .PARAMETER CheckId
        The check ID (sdaExtId) reported by the NCC task.

    .PARAMETER Cache
        Hashtable shared by the calls of one run.

    .EXAMPLE
        ResolveNxoNccCheck -Connection $c -CheckId '101061' -Cache $cache

    .OUTPUTS
        PSCustomObject with Title and Kb

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
        [ValidatePattern("^[^'/?&]+$")]
        [string]
        $CheckId,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]
        $Cache
    )

    if ($Cache.ContainsKey($CheckId)) { return $Cache[$CheckId] }

    $policy = $null
    try {
        $policy = (InvokeNxoApi -Connection $Connection -Namespace monitoring -Path "/serviceability/alerts/system-defined-policies/$CheckId").data
    } catch {
        Write-Verbose "Check $CheckId not found as extId: $($_.Exception.Message)"
        try {
            $filter = [uri]::EscapeDataString("policyId eq '$CheckId'")
            $policy = @((InvokeNxoApi -Connection $Connection -Namespace monitoring -Path "/serviceability/alerts/system-defined-policies?`$filter=$filter").data)[0]
        } catch {
            Write-Verbose "Check $CheckId could not be resolved: $($_.Exception.Message)"
        }
    }

    $title = if ($policy.title) { [string]$policy.title } elseif ($policy.name) { [string]$policy.name } else { $null }
    $result = [PSCustomObject]@{
        Title = $title
        Kb    = (@($policy.kbArticles | Where-Object { $_ }) -join ', ')
    }
    $Cache[$CheckId] = $result

    return $result
}
