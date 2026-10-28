function ShowNxoCleanupRow {
    <#
    .SYNOPSIS
        Shows the review table of a cleanup run.

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup. One line per VM / volume group and
        reason: row number, reason, name, Prism Central(s), number of recovery points, oldest
        and newest, days overdue (expired rows) and space. A * after the space means some
        recovery points of the row report no size.

    .PARAMETER Row
        Review rows.

    .EXAMPLE
        ShowNxoCleanupRow -Row $rows

    .OUTPUTS
        None (written to the host)

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive console wizard: the table is rendered to the console (Out-Host does not show up in redirected or transcribed sessions).')]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $Row
    )

    $Row | Format-Table -AutoSize -Property @(
        @{ Label = '#'; Expression = { $_.Row }; Align = 'Right' }
        @{ Label = 'Reason'; Expression = { $_.Reason } }
        @{ Label = 'VM / volume group'; Expression = { if ($_.Name.Length -gt 45) { $_.Name.Substring(0, 42) + '...' } else { $_.Name } } }
        @{ Label = 'PC'; Expression = { $_.Pcs } }
        @{ Label = 'RPs'; Expression = { $_.Count }; Align = 'Right' }
        @{ Label = 'Oldest'; Expression = { FormatNxoDate -Date $(if ($_.OldestUtc) { $_.OldestUtc.ToLocalTime() }) } }
        @{ Label = 'Newest'; Expression = { FormatNxoDate -Date $(if ($_.NewestUtc) { $_.NewestUtc.ToLocalTime() }) } }
        @{ Label = 'Overdue'; Expression = { if ($_.Reason -eq 'Expired') { '{0} d' -f $_.OverdueDays } }; Align = 'Right' }
        @{ Label = 'Space'; Expression = {
                if ($_.UnknownSize -eq $_.Count) { 'n/a' }
                elseif ($_.UnknownSize) { (FormatNxoSize -Bytes $_.SizeBytes) + '*' }
                else { FormatNxoSize -Bytes $_.SizeBytes }
            }; Align = 'Right'
        }
    ) | Out-String -Width ([Math]::Max(120, $Host.UI.RawUI.BufferSize.Width)) | Write-Host
}
