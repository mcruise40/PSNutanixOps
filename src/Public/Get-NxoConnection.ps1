function Get-NxoConnection {
    <#
    .SYNOPSIS
        Lists the Prism Central connections of the current session.

    .DESCRIPTION
        Returns one object per connection created with Connect-NxoPrismCentral (server, port,
        user name, API revision, certificate check, time of connection). The credential is not
        part of the output.

    .PARAMETER Server
        Only return these connection(s).

    .EXAMPLE
        Get-NxoConnection

    .INPUTS
        None

    .OUTPUTS
        PSCustomObject (PSNutanixOps.Connection)

    .LINK
        Connect-NxoPrismCentral
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Server
    )

    $store = GetNxoConnectionStore
    if ($store.Count -eq 0) {
        Write-Verbose 'No Prism Central connections.'
        return
    }

    foreach ($connection in (GetNxoTargetConnection -Server $Server)) {
        ConvertToNxoConnectionView -Connection $connection
    }
}
