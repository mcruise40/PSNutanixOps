function GetNxoShortId {
    <#
    .SYNOPSIS
        Returns the first 8 characters of an ID.

    .DESCRIPTION
        Internal helper for compact display of extIds. Returns ? for an empty ID.

    .PARAMETER Id
        The ID.

    .EXAMPLE
        GetNxoShortId -Id '3d0b72d3-9525-44a1-a10f-b959e2296bcc'
        Returns 3d0b72d3

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
        [AllowEmptyString()]
        [string]
        $Id
    )

    if (-not $Id) { return '?' }

    return $Id.Substring(0, [Math]::Min(8, $Id.Length))
}
