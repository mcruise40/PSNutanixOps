function ConvertFromNxoRowSelection {
    <#
    .SYNOPSIS
        Parses a row selection such as "1,4,7-12".

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup. Accepts numbers and ranges
        separated by commas, semicolons or spaces. Returns the sorted, distinct row numbers, or
        nothing if the text is not a valid selection or a number is outside 1..Max.

    .PARAMETER Text
        The selection text.

    .PARAMETER Max
        Highest row number.

    .EXAMPLE
        ConvertFromNxoRowSelection -Text '1,4,7-9' -Max 20
        Returns 1, 4, 7, 8, 9

    .OUTPUTS
        System.Int32

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]
        $Text,

        [Parameter(Mandatory)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]
        $Max
    )

    $set = [System.Collections.Generic.SortedSet[int]]::new()
    foreach ($token in ($Text -split '[,;\s]+' | Where-Object { $_ })) {
        if ($token -match '^(\d+)$') {
            $from = [int]$Matches[1]
            $to = $from
        } elseif ($token -match '^(\d+)-(\d+)$') {
            $from = [int]$Matches[1]
            $to = [int]$Matches[2]
        } else {
            return
        }
        if ($from -gt $to) { $from, $to = $to, $from }
        if ($from -lt 1 -or $to -gt $Max) { return }
        for ($number = $from; $number -le $to; $number++) { [void]$set.Add($number) }
    }

    foreach ($number in $set) { $number }
}
