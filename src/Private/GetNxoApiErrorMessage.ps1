function GetNxoApiErrorMessage {
    <#
    .SYNOPSIS
        Turns a failed Invoke-RestMethod call into a short, readable message.

    .DESCRIPTION
        Internal helper. Nutanix v4 APIs return errors as JSON (data.error[] with code and
        message). The messages are extracted and joined; without such a body the exception
        message is used. Whitespace is collapsed and the text is cut at 400 characters.

    .PARAMETER ErrorRecord
        The error record from the catch block ($_).

    .EXAMPLE
        try { Invoke-RestMethod @request } catch { GetNxoApiErrorMessage -ErrorRecord $_ }

    .OUTPUTS
        System.String

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [System.Management.Automation.ErrorRecord]
        $ErrorRecord
    )

    $message = $null
    $body = if ($ErrorRecord.ErrorDetails) { $ErrorRecord.ErrorDetails.Message } else { $null }

    if ($body) {
        try {
            $parsed = $body | ConvertFrom-Json -ErrorAction Stop
            $parts = @($parsed.data.error | Where-Object { $_ -and $_.message } | ForEach-Object {
                    if ($_.code) { '[{0}] {1}' -f $_.code, $_.message } else { [string]$_.message }
                })
            if ($parts.Count) { $message = $parts -join ' ' }
        } catch {
            Write-Verbose "$($MyInvocation.MyCommand): error body is not Nutanix JSON: $_"
        }
        if (-not $message) { $message = $body }
    }

    if (-not $message) { $message = $ErrorRecord.Exception.Message }

    $message = ([string]$message -replace '\s+', ' ').Trim()
    if ($message.Length -gt 400) { $message = $message.Substring(0, 400) + '...' }

    return $message
}
