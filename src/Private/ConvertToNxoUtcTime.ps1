function ConvertToNxoUtcTime {
    <#
    .SYNOPSIS
        Converts an API timestamp to a UTC DateTime.

    .DESCRIPTION
        Internal helper. Accepts DateTime (kind Unspecified is treated as UTC), DateTimeOffset
        and ISO-8601 strings. $null and empty strings return $null.

    .PARAMETER Timestamp
        DateTime, DateTimeOffset or ISO-8601 string.

    .EXAMPLE
        ConvertToNxoUtcTime -Timestamp '2026-10-12T16:18:16+02:00'
        Returns 2026-10-12 14:18:16 (Kind Utc).

    .OUTPUTS
        System.DateTime or $null

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [object]
        $Timestamp
    )

    if ($null -eq $Timestamp -or [string]::IsNullOrWhiteSpace([string]$Timestamp)) {
        return $null
    }
    if ($Timestamp -is [datetimeoffset]) {
        return $Timestamp.UtcDateTime
    }
    if ($Timestamp -is [datetime]) {
        if ($Timestamp.Kind -eq [System.DateTimeKind]::Unspecified) {
            return [datetime]::SpecifyKind($Timestamp, [System.DateTimeKind]::Utc)
        }
        return $Timestamp.ToUniversalTime()
    }

    $styles = [System.Globalization.DateTimeStyles]::AssumeUniversal
    return [datetimeoffset]::Parse([string]$Timestamp, [cultureinfo]::InvariantCulture, $styles).UtcDateTime
}
