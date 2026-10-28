function FormatNxoChange {
    <#
    .SYNOPSIS
        Describes a change in bytes as text.

    .DESCRIPTION
        Internal helper: "unchanged", "down by 1.5 GiB" or "up by 200.0 MiB".

    .PARAMETER Bytes
        Difference in bytes (new minus old).

    .EXAMPLE
        FormatNxoChange -Bytes -1610612736
        Returns down by 1.5 GiB

    .OUTPUTS
        System.String

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [long]
        $Bytes
    )

    if ($Bytes -eq 0) { return 'unchanged' }
    if ($Bytes -lt 0) { return 'down by {0}' -f (FormatNxoSize -Bytes (-$Bytes)) }

    return 'up by {0}' -f (FormatNxoSize -Bytes $Bytes)
}
