function InvokeNxoStorageCheck {
    <#
    .SYNOPSIS
        Measures, shows and records the cluster storage of a cleanup run.

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup. Reads the storage of all clusters
        of every Prism Central, shows it, appends it to the storage history and compares it
        with earlier live runs. A Prism Central whose storage cannot be read is reported; the
        cleanup works without it.

    .PARAMETER State
        Run state.

    .PARAMETER Pc
        The Prism Central entries of the run.

    .EXAMPLE
        InvokeNxoStorageCheck -State $state -Pc $pcs

    .OUTPUTS
        None

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive console wizard: the storage overview is part of the console output.')]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]
        $State,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object[]]
        $Pc
    )

    $measurements = @(foreach ($entry in $Pc) {
            try {
                GetNxoClusterStorage -Pc $entry
            } catch {
                $message = '{0}: storage usage could not be read ({1}). The cleanup works without it.' -f $entry.Label, $_.Exception.Message
                Write-Host "  $message" -ForegroundColor Yellow
                WriteNxoCleanupLog -State $State -Message $message -Level WARN
            }
        })
    if (-not $measurements.Count) { return }

    Write-Host 'Storage now:'
    foreach ($measurement in $measurements) {
        $text = '{0} {1}: used {2} of {3}, logical {4}' -f $measurement.Pc.Label, $measurement.Cluster, (FormatNxoSize -Bytes $measurement.UsedBytes), (FormatNxoSize -Bytes $measurement.CapacityBytes), (FormatNxoSize -Bytes $measurement.LogicalUsedBytes)
        Write-Host "  $text"
        WriteNxoCleanupLog -State $State -Message "Storage $($measurement.Pc.Address) $text"
    }

    $rows = @($measurements | ForEach-Object { ConvertToNxoStorageRow -State $State -EventName Measured -PrismCentral $_.Pc.Address -Measurement $_ })
    AddNxoStorageHistory -State $State -Row $rows
    ShowNxoStorageComparison -State $State -Current $measurements
}
