function Disconnect-NxoPrismCentral {
    <#
    .SYNOPSIS
        Removes stored Prism Central connections from the current session.

    .DESCRIPTION
        Removes the connection(s) created with Connect-NxoPrismCentral, including the stored
        credential. Without -Server all connections are removed. Prism Central keeps no
        session for these API calls, so nothing is sent to the server.

    .PARAMETER Server
        Prism Central address(es) to disconnect. Default: all.

    .EXAMPLE
        Disconnect-NxoPrismCentral

        Removes all connections.

    .EXAMPLE
        Get-NxoConnection | Where-Object Server -like '10.1.*' | Disconnect-NxoPrismCentral

        Removes the connections whose address starts with 10.1.

    .INPUTS
        System.String

    .OUTPUTS
        None

    .LINK
        Connect-NxoPrismCentral
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Server
    )

    begin {
        Write-Verbose "Starting $($MyInvocation.MyCommand)"
        $store = GetNxoConnectionStore
        # Remove everything only when no server is named and nothing is piped in: an empty
        # pipeline (e.g. a filter that matched nothing) must not disconnect all servers.
        $removeAll = -not $PSBoundParameters.ContainsKey('Server') -and -not $MyInvocation.ExpectingInput
    }

    process {
        foreach ($address in $Server) {
            $name = ConvertToNxoServerName -Server $address
            if ($store.Contains($name)) {
                $store.Remove($name)
                Write-Verbose "Disconnected from $name"
            } else {
                Write-Warning "Not connected to Prism Central '$address'."
            }
        }
    }

    end {
        if ($removeAll) {
            $count = $store.Count
            $store.Clear()
            Write-Verbose "Removed $count connection(s)."
        }
        Write-Verbose "Completed $($MyInvocation.MyCommand)"
    }
}
