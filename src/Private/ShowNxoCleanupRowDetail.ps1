function ShowNxoCleanupRowDetail {
    <#
    .SYNOPSIS
        Shows the recovery points of one review row.

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup (command "d <row>"). Shows the IDs
        of the VMs / volume groups, the newest recovery point of the entity overall (if it is
        newer than the ones in the row) and every recovery point with Prism Central, name,
        creation, expiry, space and extId.

    .PARAMETER Row
        One review row.

    .EXAMPLE
        ShowNxoCleanupRowDetail -Row $rows[4]

    .OUTPUTS
        None (written to the host)

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive console wizard: the detail view is part of the console output.')]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]
        $Row
    )

    Write-Host ''
    Write-Host ('Row {0}: {1} ({2})' -f $Row.Row, $Row.Name, $Row.Reason) -ForegroundColor Cyan
    $ids = @(@($Row.Items[0].VmIds) + @($Row.Items[0].VgIds) | Where-Object { $_ })
    Write-Host ('IDs: {0}' -f ($ids -join ', '))
    if ($Row.EntityNewestUtc -and $Row.NewestUtc -and $Row.EntityNewestUtc -gt $Row.NewestUtc) {
        Write-Host ('Newest recovery point of this VM / volume group overall: {0} (in another row or not listed)' -f (FormatNxoDate -Date $Row.EntityNewestUtc.ToLocalTime()))
    }

    $Row.Items | Sort-Object -Property CreatedUtc | Format-Table -AutoSize -Property @(
        @{ Label = 'PC'; Expression = { $_.Pc.Label } }
        @{ Label = 'Recovery point'; Expression = { $_.RpName } }
        @{ Label = 'Created'; Expression = { FormatNxoDate -Date $(if ($_.CreatedUtc) { $_.CreatedUtc.ToLocalTime() }) } }
        @{ Label = 'Expires'; Expression = { FormatNxoDate -Date $(if ($_.ExpiresUtc) { $_.ExpiresUtc.ToLocalTime() }) -Empty 'never' } }
        @{ Label = 'Space'; Expression = { FormatNxoSize -Bytes $_.SizeBytes }; Align = 'Right' }
        @{ Label = 'ExtId'; Expression = { $_.RpExtId } }
    ) | Out-String -Width ([Math]::Max(120, $Host.UI.RawUI.BufferSize.Width)) | Write-Host
}
