function FormatNxoTotal {
    <#
    .SYNOPSIS
        Formats the total space of recovery points as a lower bound.

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup. Sums SizeBytes of the items that
        report a size. "at least" because exclusive usage does not include data shared between
        several deleted recovery points. Items without size are mentioned separately.

    .PARAMETER Item
        Items with a SizeBytes property ($null = unknown).

    .EXAMPLE
        FormatNxoTotal -Item $selectedItems

    .OUTPUTS
        System.String

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $Item
    )

    $known = @($Item | Where-Object { $null -ne $_.SizeBytes })
    if (-not $known.Count) { return 'unknown (no size reported)' }

    $text = 'at least ' + (FormatNxoSize -Bytes ($known | Measure-Object -Property SizeBytes -Sum).Sum)
    $unknown = @($Item).Count - $known.Count
    if ($unknown) { $text += ' (plus {0} without size)' -f (FormatNxoCount -Count $unknown -Singular 'recovery point') }

    return $text
}
