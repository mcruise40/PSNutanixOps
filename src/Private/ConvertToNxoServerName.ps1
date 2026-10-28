function ConvertToNxoServerName {
    <#
    .SYNOPSIS
        Normalizes a Prism Central address.

    .DESCRIPTION
        Internal helper. Removes a leading https:// or http://, any path, the default port
        9440 and surrounding whitespace, and converts the result to lower case. The result is
        used as key in the connection store, so "PC01.example.local", "https://pc01.example.local:9440/"
        and "pc01.example.local" refer to the same connection.

    .PARAMETER Server
        IP address, FQDN or URL of a Prism Central instance.

    .EXAMPLE
        ConvertToNxoServerName -Server 'https://PC01.example.local:9440/console'
        Returns: pc01.example.local

    .OUTPUTS
        System.String

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Server
    )

    $name = $Server.Trim() -replace '^https?://', ''
    $name = $name -replace '/.*$', ''
    $name = $name -replace ':9440$', ''

    if (-not $name) {
        throw [System.ArgumentException]::new("'$Server' is not a valid Prism Central address.", 'Server')
    }

    return $name.ToLowerInvariant()
}
