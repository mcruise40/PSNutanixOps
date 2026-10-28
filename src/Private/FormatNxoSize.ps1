function FormatNxoSize {
    <#
    .SYNOPSIS
        Formats a byte count with binary units.

    .DESCRIPTION
        Internal helper. -Unit Auto picks the largest unit (B, KiB, MiB, GiB, TiB, PiB) with a
        value of at least 1. A fixed unit (GiB, TiB) always uses that unit. $null returns 'n/a'.

    .PARAMETER Bytes
        Byte count.

    .PARAMETER Unit
        Auto (default), GiB or TiB.

    .EXAMPLE
        FormatNxoSize -Bytes 1610612736
        Returns 1.5 GiB

    .EXAMPLE
        FormatNxoSize -Bytes 5497558138880 -Unit TiB
        Returns 5.00 TiB

    .OUTPUTS
        System.String

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]
        $Bytes,

        [Parameter()]
        [ValidateSet('Auto', 'GiB', 'TiB')]
        [string]
        $Unit = 'Auto'
    )

    if ($null -eq $Bytes -or [string]::IsNullOrWhiteSpace([string]$Bytes)) {
        return 'n/a'
    }

    $value = [double]$Bytes
    $culture = [cultureinfo]::InvariantCulture

    switch ($Unit) {
        'GiB' { return [string]::Format($culture, '{0:N0} GiB', $value / 1GB) }
        'TiB' { return [string]::Format($culture, '{0:N2} TiB', $value / 1TB) }
    }

    $units = @('B', 'KiB', 'MiB', 'GiB', 'TiB', 'PiB')
    $index = 0
    while ([Math]::Abs($value) -ge 1024 -and $index -lt $units.Count - 1) {
        $value /= 1024
        $index++
    }
    if ($index -eq 0) {
        return [string]::Format($culture, '{0:N0} {1}', $value, $units[$index])
    }

    return [string]::Format($culture, '{0:N1} {1}', $value, $units[$index])
}
