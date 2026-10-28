function GetNxoTargetConnection {
    <#
    .SYNOPSIS
        Returns the stored connection objects a command should work on.

    .DESCRIPTION
        Internal helper used by every public command that talks to Prism Central. Without
        -Server all stored connections are returned. With -Server only the named connections
        are returned; a name that is not connected is an error.

    .PARAMETER Server
        Optional Prism Central address(es) to restrict the result to.

    .EXAMPLE
        GetNxoTargetConnection
        Returns all connections created with Connect-NxoPrismCentral.

    .EXAMPLE
        GetNxoTargetConnection -Server 'pc01.example.local'
        Returns only the connection to pc01.example.local.

    .OUTPUTS
        PSCustomObject (PSNutanixOps.ConnectionState)

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter()]
        [string[]]
        $Server
    )

    $store = GetNxoConnectionStore
    if ($store.Count -eq 0) {
        throw [System.InvalidOperationException]::new('Not connected to any Prism Central. Run Connect-NxoPrismCentral first.')
    }

    $requested = @($Server | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (-not $requested.Count) {
        $store.Values
        return
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($name in $requested) {
        $key = ConvertToNxoServerName -Server $name
        if (-not $store.Contains($key)) {
            throw [System.InvalidOperationException]::new("Not connected to Prism Central '$name'. Run Connect-NxoPrismCentral -Server $name first.")
        }
        if ($seen.Add($key)) {
            $store[$key]
        }
    }
}
