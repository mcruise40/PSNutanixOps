function TestNxoVersionLower {
    <#
    .SYNOPSIS
        Tests whether an installed version is lower than an available one.

    .DESCRIPTION
        Internal helper, e.g. for Nutanix Guest Tools (installed 4.3.1, available 4.5.1.8).
        Compares as [version] when both strings parse, otherwise falls back to "not equal".
        Returns $null if one of the values is missing.

    .PARAMETER Installed
        Installed version.

    .PARAMETER Available
        Available version.

    .EXAMPLE
        TestNxoVersionLower -Installed '4.3.1' -Available '4.5.1.8'
        Returns $true

    .OUTPUTS
        System.Boolean or $null

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]
        $Installed,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]
        $Available
    )

    if ([string]::IsNullOrWhiteSpace($Installed) -or [string]::IsNullOrWhiteSpace($Available)) {
        return $null
    }

    $installedVersion = $null
    $availableVersion = $null
    if ([version]::TryParse($Installed.Trim(), [ref]$installedVersion) -and [version]::TryParse($Available.Trim(), [ref]$availableVersion)) {
        return $installedVersion -lt $availableVersion
    }

    return $Installed.Trim() -ne $Available.Trim()
}
