function Connect-NxoPrismCentral {
    <#
    .SYNOPSIS
        Connects to one or more Nutanix Prism Central instances.

    .DESCRIPTION
        Checks the login against the Prism Central v4 API and stores the connection for the
        current PowerShell session. All other PSNutanixOps commands work on the stored
        connections, by default on all of them, or on the ones named with their -Server
        parameter. Connecting to an address that is already connected replaces that connection.

        The login check reads one VM (vmm namespace). It also negotiates the API revision: the
        given -ApiVersion is tried first, then v4.3 down to v4.0.

        Certificates are validated by default. Prism Central often uses a self-signed
        certificate; use -SkipCertificateCheck in that case.

    .PARAMETER Server
        IP address(es) or FQDN(s) of Prism Central, without https:// or port.

    .PARAMETER Credential
        Prism Central login. The same login is used for every address in -Server.

    .PARAMETER ApiVersion
        Preferred Nutanix v4 API revision. Default: v4.2.

    .PARAMETER Port
        Prism Central API port. Default: 9440.

    .PARAMETER SkipCertificateCheck
        Do not validate the TLS certificate of Prism Central (self-signed certificates).

    .EXAMPLE
        Connect-NxoPrismCentral -Server pc01.example.local -Credential (Get-Credential) -SkipCertificateCheck

        Connects to one Prism Central with a self-signed certificate.

    .EXAMPLE
        $cred = Get-Credential
        Connect-NxoPrismCentral -Server 10.0.20.10, 10.1.20.10 -Credential $cred

        Connects to two Prism Central instances with the same login.

    .INPUTS
        System.String

    .OUTPUTS
        PSCustomObject (PSNutanixOps.Connection)

    .LINK
        Disconnect-NxoPrismCentral

    .LINK
        Get-NxoConnection
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('PcIp', 'PrismCentral')]
        [string[]]
        $Server,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential,

        [Parameter()]
        [ValidatePattern('^v4\.\d+$')]
        [string]
        $ApiVersion = 'v4.2',

        [Parameter()]
        [ValidateRange(1, 65535)]
        [int]
        $Port = 9440,

        [Parameter()]
        [switch]
        $SkipCertificateCheck
    )

    begin {
        Write-Verbose "Starting $($MyInvocation.MyCommand)"
        $store = GetNxoConnectionStore
    }

    process {
        foreach ($address in $Server) {
            $name = ConvertToNxoServerName -Server $address
            $connection = [PSCustomObject]@{
                Server               = $name
                Port                 = $Port
                Credential           = $Credential
                ApiVersion           = $ApiVersion
                SkipCertificateCheck = [bool]$SkipCertificateCheck
                ConnectedAt          = Get-Date
                NamespaceVersion     = @{}
            }
            $connection.PSObject.TypeNames.Insert(0, 'PSNutanixOps.ConnectionState')

            try {
                $null = InvokeNxoApi -Connection $connection -Namespace vmm -Path '/ahv/config/vms?$limit=1'
            } catch {
                $failure = $_
                Write-Verbose "$($MyInvocation.MyCommand) failed for '$name': $failure"
                $statusCode = GetNxoStatusCode -Exception $failure.Exception
                $reason = switch ($statusCode) {
                    401 { 'login failed: wrong user name or password' }
                    403 { 'login works, but this user may not read VMs' }
                    404 { "the v4 API is not available (tried $ApiVersion and v4.3 to v4.0)" }
                    $null {
                        $hint = if (-not $SkipCertificateCheck -and $failure.Exception.ToString() -match 'SSL|certificate|trust') { ' The certificate is not trusted; use -SkipCertificateCheck for a self-signed certificate.' } else { '' }
                        "cannot connect to https://${name}:$Port ($($failure.Exception.Message)).$hint"
                    }
                    default { $failure.Exception.Message }
                }
                $exception = [System.InvalidOperationException]::new("Could not connect to Prism Central '$name': $reason", $failure.Exception)
                $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                    $exception, 'NxoConnectFailed', [System.Management.Automation.ErrorCategory]::ConnectionError, $name)
                $PSCmdlet.WriteError($errorRecord)
                continue
            }

            $store[$name] = $connection
            Write-Verbose "Connected to $name as $($Credential.UserName)"
            ConvertToNxoConnectionView -Connection $connection
        }
    }

    end {
        Write-Verbose "Completed $($MyInvocation.MyCommand)"
    }
}
