function InvokeNxoRestMethod {
    <#
    .SYNOPSIS
        Sends one request to the Prism Central REST API of a connection.

    .DESCRIPTION
        Internal helper and the only place that calls Invoke-RestMethod.
        - Authenticates with the connection's credential (HTTP Basic over HTTPS).
        - Adds the NTNX-Request-Id idempotency header on every write request (mandatory for
          v4 POST/PUT/DELETE).
        - Retries when Prism Central reports its API rate limit (HTTP 429), honouring a
          Retry-After header, otherwise waiting 5, 10, 20, 40 and 60 seconds.
        - On failure throws an exception whose message contains the Nutanix error text and
          whose Data['StatusCode'] holds the HTTP status (or $null without HTTP answer).

    .PARAMETER Connection
        Connection object from the connection store.

    .PARAMETER Path
        Request path below /api, e.g. /vmm/v4.2/ahv/config/vms?$limit=1.

    .PARAMETER Method
        HTTP method. Default: GET.

    .PARAMETER Body
        Request body; converted to JSON.

    .PARAMETER TimeoutSec
        Timeout per request in seconds. Default: 120.

    .PARAMETER MaxRetry
        Maximum number of retries after a rate-limit answer. Default: 5.

    .EXAMPLE
        InvokeNxoRestMethod -Connection $connection -Path '/vmm/v4.2/ahv/config/vms?$limit=1'

    .OUTPUTS
        PSCustomObject (the parsed JSON response)

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]
        $Connection,

        [Parameter(Mandatory)]
        [ValidatePattern('^/')]
        [string]
        $Path,

        [Parameter()]
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE')]
        [string]
        $Method = 'GET',

        [Parameter()]
        [AllowNull()]
        [object]
        $Body,

        [Parameter()]
        [ValidateRange(1, 3600)]
        [int]
        $TimeoutSec = 120,

        [Parameter()]
        [ValidateRange(0, 5)]
        [int]
        $MaxRetry = 5
    )

    $request = @{
        Method               = $Method
        Uri                  = 'https://{0}:{1}/api{2}' -f $Connection.Server, $Connection.Port, $Path
        Authentication       = 'Basic'
        Credential           = $Connection.Credential
        TimeoutSec           = $TimeoutSec
        SkipHeaderValidation = $true
        ErrorAction          = 'Stop'
    }
    if ($Connection.SkipCertificateCheck) {
        $request.SkipCertificateCheck = $true
    }
    if ($Method -ne 'GET') {
        $request.Headers = @{ 'NTNX-Request-Id' = [guid]::NewGuid().Guid }
    }
    if ($null -ne $Body) {
        $request.Body = ConvertTo-Json -InputObject $Body -Depth 20
        $request.ContentType = 'application/json'
    }

    $waits = @(5, 10, 20, 40, 60)
    for ($attempt = 0; ; $attempt++) {
        try {
            return Invoke-RestMethod @request
        } catch {
            $statusCode = GetNxoStatusCode -Exception $_.Exception
            $message = GetNxoApiErrorMessage -ErrorRecord $_

            $isRateLimit = $statusCode -eq 429 -or $message -match 'rate limit'
            if ($isRateLimit -and $attempt -lt $MaxRetry) {
                $wait = $waits[[Math]::Min($attempt, $waits.Count - 1)]
                try {
                    $retryAfter = $_.Exception.Response.Headers.RetryAfter.Delta
                    if ($retryAfter) { $wait = [Math]::Min(120, [Math]::Max(1, [int]$retryAfter.TotalSeconds)) }
                } catch {
                    Write-Verbose "$($MyInvocation.MyCommand): no Retry-After header: $_"
                }
                Write-Warning ('Prism Central {0}: API rate limit reached, waiting {1} s before retry {2}.' -f $Connection.Server, $wait, ($attempt + 1))
                Start-Sleep -Seconds $wait
                continue
            }

            Write-Verbose "$($MyInvocation.MyCommand) failed for '$Method $Path' on $($Connection.Server): $message"
            $exception = [System.Exception]::new(('Nutanix API call failed ({0} {1} on {2}): {3}' -f $Method, $Path, $Connection.Server, $message), $_.Exception)
            $exception.Data['StatusCode'] = $statusCode
            $errorRecord = [System.Management.Automation.ErrorRecord]::new(
                $exception, 'NxoApiRequestFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $Path)
            $PSCmdlet.ThrowTerminatingError($errorRecord)
        }
    }
}
