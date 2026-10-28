function GetNxoLookupState {
    <#
    .SYNOPSIS
        Checks whether an entity exists: Exists, Missing or Unverified.

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup. Reads the entity by ID. HTTP 404
        means Missing; any other error (permissions, connection, ...) means Unverified, so an
        entity is never reported missing just because it could not be read.

    .PARAMETER Connection
        Connection object from the connection store.

    .PARAMETER Namespace
        API namespace, e.g. vmm.

    .PARAMETER Path
        Entity path below the revision, e.g. /ahv/config/vms/{extId}.

    .EXAMPLE
        GetNxoLookupState -Connection $c -Namespace vmm -Path "/ahv/config/vms/$id"

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
        [ValidatePattern('^[a-z]+$')]
        [string]
        $Namespace,

        [Parameter(Mandatory)]
        [ValidatePattern('^/')]
        [string]
        $Path
    )

    try {
        $null = InvokeNxoApi -Connection $Connection -Namespace $Namespace -Path $Path
        return 'Exists'
    } catch {
        if ((GetNxoStatusCode -Exception $_.Exception) -eq 404) { return 'Missing' }
        Write-Verbose "$($MyInvocation.MyCommand) could not verify '$Namespace$Path': $($_.Exception.Message)"
        return 'Unverified'
    }
}
