function TestNxoCleanupAccess {
    <#
    .SYNOPSIS
        Checks that a login can read VMs and recovery points.

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup. Returns $null if the login works
        and can read VMs and recovery points, otherwise a readable description of the problem.

    .PARAMETER Connection
        Connection object from the connection store.

    .EXAMPLE
        TestNxoCleanupAccess -Connection $c

    .OUTPUTS
        System.String or $null

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]
        $Connection
    )

    try {
        $null = InvokeNxoApi -Connection $Connection -Namespace vmm -Path '/ahv/config/vms?$limit=1'
        $null = InvokeNxoApi -Connection $Connection -Namespace dataprotection -Path '/config/recovery-points?$limit=1'
        return $null
    } catch {
        # Inside the switch below $_ is the status code, so the error is kept in $failure.
        $failure = $_
        $statusCode = GetNxoStatusCode -Exception $failure.Exception
        switch ($statusCode) {
            $null { return "cannot connect to https://$($Connection.Server):$($Connection.Port) - $($failure.Exception.Message)" }
            401 { return 'login failed: wrong user name or password' }
            403 { return 'login works, but this user may not read VMs or recovery points' }
            404 { return 'the v4 API (vmm or dataprotection) is not available on this Prism Central' }
            default { return 'HTTP {0}: {1}' -f $statusCode, $failure.Exception.Message }
        }
    }
}
