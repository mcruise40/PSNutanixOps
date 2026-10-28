function ConvertToNxoPercent {
    <#
    .SYNOPSIS
        Converts a ppm value of the stats APIs to percent.

    .DESCRIPTION
        Internal helper. The v4 stats APIs report ratios such as CPU usage and CPU Ready in
        parts per million: 10'000 ppm = 1 %. The result is rounded to two decimals. $null
        stays $null.

    .PARAMETER Ppm
        Value in parts per million.

    .EXAMPLE
        ConvertToNxoPercent -Ppm 123456
        Returns 12.35

    .OUTPUTS
        System.Double or $null

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([double])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]
        $Ppm
    )

    if ($null -eq $Ppm -or [string]::IsNullOrWhiteSpace([string]$Ppm)) {
        return $null
    }

    return [Math]::Round([double]$Ppm / 10000, 2)
}
