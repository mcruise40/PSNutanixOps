function ResolveNxoCategoryExtId {
    <#
    .SYNOPSIS
        Returns the extId of a category key/value pair, or $null if it does not exist.

    .DESCRIPTION
        Internal helper. Uses an OData filter on prism config/categories (URL-encoded). Key and
        value must not contain single quotes, as they would end the OData string literal.

    .PARAMETER Connection
        Connection object from the connection store.

    .PARAMETER Key
        Category key, e.g. Patching.

    .PARAMETER Value
        Category value, e.g. Group01.

    .EXAMPLE
        ResolveNxoCategoryExtId -Connection $connection -Key 'Patching' -Value 'Group01'

    .OUTPUTS
        System.String or $null

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]
        $Connection,

        [Parameter(Mandatory)]
        [ValidatePattern("^[^']+$")]
        [string]
        $Key,

        [Parameter(Mandatory)]
        [ValidatePattern("^[^']+$")]
        [string]
        $Value
    )

    $filter = [uri]::EscapeDataString(("key eq '{0}' and value eq '{1}'" -f $Key, $Value))

    $response = InvokeNxoApi -Connection $Connection -Namespace prism -Path ('/config/categories?$filter={0}' -f $filter)
    $match = @($response.data | Where-Object { $null -ne $_ }) | Select-Object -First 1

    if ($null -eq $match) { return $null }

    return [string]$match.extId
}
