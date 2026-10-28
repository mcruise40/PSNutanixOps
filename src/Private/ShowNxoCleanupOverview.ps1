function ShowNxoCleanupOverview {
    <#
    .SYNOPSIS
        Shows the review table with totals and the legend of the reasons.

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup (step 3 and command "list").

    .PARAMETER Row
        Review rows.

    .PARAMETER Candidate
        All candidate recovery points.

    .PARAMETER Pc
        The Prism Central entries of the run (Label, Address).

    .EXAMPLE
        ShowNxoCleanupOverview -Row $rows -Candidate $candidates -Pc $pcs

    .OUTPUTS
        None

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive console wizard: the overview is part of the console output.')]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $Row,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $Candidate,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $Pc
    )

    ShowNxoCleanupRow -Row $Row
    Write-Host ('Prism Centrals: ' + (($Pc | ForEach-Object { '{0} = {1}' -f $_.Label, $_.Address }) -join ', '))
    if ($Row | Where-Object { $_.UnknownSize -and $_.UnknownSize -lt $_.Count }) {
        Write-Host '* some recovery points in this row report no size; the value shown is the known part.'
    }

    $byReason = $Candidate | Group-Object -Property Reason | ForEach-Object { '{0} {1}' -f $_.Count, $_.Name }
    Write-Host ('{0} in {1} ({2}), space: {3}' -f (FormatNxoCount -Count @($Candidate).Count -Singular 'recovery point'), (FormatNxoCount -Count @($Row).Count -Singular 'row'),
        ($byReason -join ', '), (FormatNxoTotal -Item $Candidate))

    $legend = [ordered]@{
        'VM missing'  = 'the VM no longer exists on any Prism Central checked'
        'VG missing'  = 'the volume group no longer exists on any Prism Central checked'
        'VM replaced' = 'the VM no longer exists, but another VM has the same name (restored or re-created?) - check before deleting'
        'Expired'     = 'past its expiry date but still there; the VM / volume group still exists'
    }
    foreach ($reason in $legend.Keys) {
        if (@($Row.Reason) -contains $reason) { Write-Host ('  {0,-12} {1}' -f $reason, $legend[$reason]) }
    }
}
