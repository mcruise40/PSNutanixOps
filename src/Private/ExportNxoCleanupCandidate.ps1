function ExportNxoCleanupCandidate {
    <#
    .SYNOPSIS
        Exports the review list of a cleanup run to CSV.

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup. One line per recovery point with
        row, reason, name, type, Prism Central, recovery point name and IDs, creation, expiry,
        size and the VM / volume group IDs. Uses the list separator of the machine and UTF-8
        with BOM, so Excel opens it directly. Not suppressed by -WhatIf.

    .PARAMETER State
        Run state (LogFile).

    .PARAMETER Row
        Review rows.

    .PARAMETER Path
        CSV file.

    .EXAMPLE
        ExportNxoCleanupCandidate -State $state -Row $rows -Path .\rp-list.csv

    .OUTPUTS
        None

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive console wizard: the export confirmation is part of the console output.')]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]
        $State,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $Row,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path
    )

    $lines = @(foreach ($entry in $Row) {
            foreach ($item in $entry.Items) {
                [PSCustomObject][ordered]@{
                    Row                = $entry.Row
                    Reason             = $entry.Reason
                    Name               = $entry.Name
                    Type               = $item.Type
                    PrismCentral       = $item.Pc.Address
                    RecoveryPointName  = $item.RpName
                    RecoveryPointExtId = $item.RpExtId
                    LocationAgnosticId = $item.LocationAgnosticId
                    Created            = FormatNxoDate -Date $(if ($item.CreatedUtc) { $item.CreatedUtc.ToLocalTime() })
                    Expires            = FormatNxoDate -Date $(if ($item.ExpiresUtc) { $item.ExpiresUtc.ToLocalTime() }) -Empty 'never'
                    SizeBytes          = $item.SizeBytes
                    Size               = FormatNxoSize -Bytes $item.SizeBytes
                    VmExtIds           = @($item.VmIds) -join ' '
                    VolumeGroupExtIds  = @($item.VgIds) -join ' '
                }
            }
        })

    $lines | Export-Csv -LiteralPath $Path -NoTypeInformation -UseCulture -Encoding utf8BOM -WhatIf:$false -Confirm:$false
    Write-Host ('Exported {0} to {1}' -f (FormatNxoCount -Count $lines.Count -Singular 'recovery point'), $Path) -ForegroundColor Green
    WriteNxoCleanupLog -State $State -Message "Exported list to $Path"
}
