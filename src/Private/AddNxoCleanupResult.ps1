function AddNxoCleanupResult {
    <#
    .SYNOPSIS
        Records, shows and logs the outcome for one recovery point of a cleanup run.

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup. Adds a result row to State.Results
        (later written to the results CSV), prints a coloured line and writes the log.

    .PARAMETER State
        Run state (Results, LogFile).

    .PARAMETER Item
        The candidate (recovery point) the result is for.

    .PARAMETER Status
        Deleted, Already gone, Failed, Timeout, Not confirmed, Not deleted (dry run) or
        Skipped (not confirmed).

    .PARAMETER Message
        Optional detail.

    .EXAMPLE
        AddNxoCleanupResult -State $state -Item $item -Status Deleted

    .OUTPUTS
        None

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive console wizard: the per-item result line is part of the console output.')]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]
        $State,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]
        $Item,

        [Parameter(Mandatory)]
        [ValidateSet('Deleted', 'Already gone', 'Failed', 'Timeout', 'Not confirmed', 'Not deleted (dry run)', 'Skipped (not confirmed)')]
        [string]
        $Status,

        [Parameter()]
        [string]
        $Message
    )

    $State.Results.Add([PSCustomObject][ordered]@{
            Time               = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Status             = $Status
            Reason             = $Item.Reason
            Name               = $Item.Name
            PrismCentral       = $Item.Pc.Address
            RecoveryPointName  = $Item.RpName
            RecoveryPointExtId = $Item.RpExtId
            SizeBytes          = $Item.SizeBytes
            Message            = $Message
        })

    $text = '{0}: {1} / {2} on {3}' -f $Status, $Item.Name, $Item.RpName, $Item.Pc.Label
    if ($Message) { $text += " - $Message" }
    $ok = $Status -in @('Deleted', 'Already gone', 'Not deleted (dry run)', 'Skipped (not confirmed)')
    $color = if ($Status -eq 'Skipped (not confirmed)') { 'Yellow' } elseif ($ok) { 'Green' } else { 'Red' }
    Write-Host "  $text" -ForegroundColor $color

    $level = if ($ok) { 'INFO' } else { 'ERROR' }
    WriteNxoCleanupLog -State $State -Message ('{0} [{1}] on {2}' -f $text, $Item.RpExtId, $Item.Pc.Address) -Level $level
}
