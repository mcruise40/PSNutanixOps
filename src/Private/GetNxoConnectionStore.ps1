function GetNxoConnectionStore {
    <#
    .SYNOPSIS
        Returns the module-wide store of Prism Central connections.

    .DESCRIPTION
        Internal helper. The store is an ordered dictionary keyed by the normalized server
        name (see ConvertToNxoServerName). It is created on first use, so the module does not
        depend on initialization code at import time.

    .OUTPUTS
        System.Collections.Specialized.OrderedDictionary

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param ()

    if ($null -eq $script:NxoConnections) {
        $script:NxoConnections = [ordered]@{}
    }

    # Dictionaries are not enumerated by the pipeline, so the store itself is returned.
    return $script:NxoConnections
}
