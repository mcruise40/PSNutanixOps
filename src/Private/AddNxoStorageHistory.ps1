function AddNxoStorageHistory {
    <#
    .SYNOPSIS
        Appends rows to the cleanup storage history CSV.

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup. The history file
        (RecoveryPointCleanup_storage-history.csv in the log folder) lets later runs compare
        the storage with the state before a deletion. Uses the list separator of the machine
        and UTF-8 with BOM, so Excel opens it directly. Never suppressed by -WhatIf; a write
        error is shown and logged but does not stop the run.

    .PARAMETER State
        Run state (StorageFile, LogFile).

    .PARAMETER Row
        Rows from ConvertToNxoStorageRow.

    .EXAMPLE
        AddNxoStorageHistory -State $state -Row $rows

    .OUTPUTS
        None

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive console wizard: problems are shown in the wizard output.')]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]
        $State,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $Row
    )

    if (-not @($Row).Count) { return }

    try {
        $Row | Export-Csv -LiteralPath $State.StorageFile -Append -NoTypeInformation -UseCulture -Encoding utf8BOM -WhatIf:$false -Confirm:$false
    } catch {
        Write-Host "  Storage history could not be written: $($_.Exception.Message)" -ForegroundColor Yellow
        WriteNxoCleanupLog -State $State -Message "Storage history could not be written: $($_.Exception.Message)" -Level WARN
    }
}
