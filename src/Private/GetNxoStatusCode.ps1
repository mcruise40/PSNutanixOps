function GetNxoStatusCode {
    <#
    .SYNOPSIS
        Returns the HTTP status code carried by an exception, or $null.

    .DESCRIPTION
        Internal helper. Walks the exception and its inner exceptions and returns the first
        status code found, either stored by InvokeNxoRestMethod in Exception.Data['StatusCode']
        or exposed by the original HTTP response (Exception.Response.StatusCode).
        $null means the request got no HTTP answer at all (DNS, TLS, timeout, ...).

    .PARAMETER Exception
        The exception to inspect, typically $_.Exception inside a catch block.

    .EXAMPLE
        try { InvokeNxoRestMethod @request } catch { GetNxoStatusCode -Exception $_.Exception }

    .OUTPUTS
        System.Int32 or $null

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [System.Exception]
        $Exception
    )

    $current = $Exception
    while ($null -ne $current) {
        if ($current.Data -and $current.Data.Contains('StatusCode') -and $null -ne $current.Data['StatusCode']) {
            return [int]$current.Data['StatusCode']
        }
        $responseProperty = $current.PSObject.Properties['Response']
        if ($responseProperty -and $responseProperty.Value -and $responseProperty.Value.StatusCode) {
            return [int]$responseProperty.Value.StatusCode
        }
        $current = $current.InnerException
    }

    return $null
}
