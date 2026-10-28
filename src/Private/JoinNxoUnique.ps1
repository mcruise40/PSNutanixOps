function JoinNxoUnique {
    <#
    .SYNOPSIS
        Joins the distinct, non-empty values of a list into one string.

    .DESCRIPTION
        Internal helper for CSV-friendly output columns (MAC addresses, IPs, categories, ...).
        Order of first appearance is kept. Returns $null if nothing is left.

    .PARAMETER Value
        Values to join.

    .PARAMETER Separator
        Separator. Default: ', '.

    .EXAMPLE
        JoinNxoUnique -Value @('10.0.0.5', $null, '10.0.0.5', '10.0.0.6')
        Returns 10.0.0.5, 10.0.0.6

    .OUTPUTS
        System.String or $null

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]
        $Value,

        [Parameter()]
        [string]
        $Separator = ', '
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $list = foreach ($item in @($Value)) {
        if ($null -eq $item) { continue }
        $text = [string]$item
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($seen.Add($text)) { $text }
    }
    $list = @($list)

    if (-not $list.Count) { return $null }

    return $list -join $Separator
}
