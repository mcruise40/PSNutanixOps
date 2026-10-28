function FormatNxoDate {
    <#
    .SYNOPSIS
        Formats an optional date, returning a placeholder for $null.

    .DESCRIPTION
        Internal helper for reports and console output.

    .PARAMETER Date
        The date (DateTime or $null).

    .PARAMETER Format
        .NET format string. Default: yyyy-MM-dd HH:mm.

    .PARAMETER Empty
        Text for $null. Default: empty string.

    .EXAMPLE
        FormatNxoDate -Date (Get-Date) -Format 'HH:mm'

    .OUTPUTS
        System.String

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [object]
        $Date,

        [Parameter(Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Format = 'yyyy-MM-dd HH:mm',

        [Parameter()]
        [string]
        $Empty = ''
    )

    if ($null -eq $Date -or [string]::IsNullOrWhiteSpace([string]$Date)) { return $Empty }

    return ([datetime]$Date).ToString($Format, [cultureinfo]::InvariantCulture)
}
