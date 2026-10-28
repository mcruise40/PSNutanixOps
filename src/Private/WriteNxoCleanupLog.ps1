function WriteNxoCleanupLog {
    <#
    .SYNOPSIS
        Appends a line to the log file of a recovery point cleanup run.

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup. Format:
        yyyy-MM-dd HH:mm:ss [LEVEL] message. Writing the log is never suppressed by -WhatIf,
        so dry runs are logged too.

    .PARAMETER State
        Run state (hashtable with LogFile).

    .PARAMETER Message
        Log text.

    .PARAMETER Level
        INFO (default), WARN or ERROR.

    .EXAMPLE
        WriteNxoCleanupLog -State $state -Message 'Step 1: Connect'

    .OUTPUTS
        None

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]
        $State,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Message,

        [Parameter()]
        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]
        $Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $State.LogFile -Value $line -Encoding utf8 -WhatIf:$false -Confirm:$false
}
