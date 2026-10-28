function ConvertToNxoConnectionView {
    <#
    .SYNOPSIS
        Returns the public view of a stored connection.

    .DESCRIPTION
        Internal helper. The stored connection carries the credential and the negotiated API
        revisions; the view shows what a user needs to see and keeps the credential out of
        the pipeline.

    .PARAMETER Connection
        Connection object from the connection store.

    .EXAMPLE
        ConvertToNxoConnectionView -Connection $connection

    .OUTPUTS
        PSCustomObject (PSNutanixOps.Connection)

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]
        $Connection
    )

    $view = [PSCustomObject][ordered]@{
        Server               = $Connection.Server
        Port                 = $Connection.Port
        UserName             = $Connection.Credential.UserName
        ApiVersion           = $Connection.ApiVersion
        SkipCertificateCheck = $Connection.SkipCertificateCheck
        ConnectedAt          = $Connection.ConnectedAt
    }
    $view.PSObject.TypeNames.Insert(0, 'PSNutanixOps.Connection')

    return $view
}
