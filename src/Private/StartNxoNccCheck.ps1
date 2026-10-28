function StartNxoNccCheck {
    <#
    .SYNOPSIS
        Starts the NCC health checks on one cluster.

    .DESCRIPTION
        Internal helper for Test-NxoUpgradeReadiness. Calls monitoring
        serviceability/clusters/{id}/$actions/run-system-defined-checks with all checks.

        The API needs a recipient for the run summary: the alert email configuration of Prism
        Central (used when no recipient is known) or additional recipients. Without an alert
        email on Prism Central the request is either rejected (NCC-40031) or accepted and the
        task fails a few seconds later. In both cases the engineer is asked once per run for
        an address (interactive runs only); the answer is kept in State.Recipients.

    .PARAMETER Connection
        Connection object from the connection store.

    .PARAMETER ClusterExtId
        External ID of the cluster.

    .PARAMETER ClusterName
        Cluster name, for messages.

    .PARAMETER State
        Hashtable shared by the clusters of one run: Recipients (string[]) and Asked (bool).

    .PARAMETER NonInteractive
        Never prompt for a recipient.

    .EXAMPLE
        StartNxoNccCheck -Connection $c -ClusterExtId $cl.extId -ClusterName $cl.name -State $state

    .OUTPUTS
        System.Collections.Hashtable with TaskId, Started and Error

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive console prompt: the explanation must be shown next to Read-Host, not in an output stream.')]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]
        $Connection,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ClusterExtId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ClusterName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]
        $State,

        [Parameter()]
        [switch]
        $NonInteractive
    )

    $noRecipient = 'No recipient for the NCC run summary: no alert email is configured on Prism Central. Use -NccReportRecipient or configure the alert email on Prism Central.'

    for ($attempt = 1; $attempt -le 2; $attempt++) {
        $missingRecipient = $false
        $recipients = @($State.Recipients | Where-Object { $_ })
        try {
            $body = @{ shouldRunAllChecks = $true; shouldAnonymize = $false }
            if ($recipients.Count) {
                $body.shouldSendReportToConfiguredRecipients = $false
                $body.additionalRecipients = $recipients
            } else {
                $body.shouldSendReportToConfiguredRecipients = $true
            }
            $response = InvokeNxoApi -Connection $Connection -Namespace monitoring -Method POST -Path "/serviceability/clusters/$ClusterExtId/`$actions/run-system-defined-checks" -Body $body
            $taskId = $response.data.extId

            if (-not $recipients.Count) {
                # Detect the asynchronous "no email configured" failure early.
                Start-Sleep -Seconds 5
                $task = (InvokeNxoApi -Connection $Connection -Namespace prism -Path "/config/tasks/$taskId").data
                $taskMessage = (@($task.errorMessages | ForEach-Object { $_.message }) | Where-Object { $_ }) -join ' '
                if ($task.status -eq 'FAILED' -and $taskMessage -match 'no email configured') { $missingRecipient = $true }
            }
            if (-not $missingRecipient) {
                Write-Verbose "NCC started on $ClusterName (task $taskId)"
                return @{ TaskId = $taskId; Started = Get-Date; Error = $null }
            }
        } catch {
            if ($_.Exception.Message -notmatch 'NCC-40031|no email configured') {
                Write-Verbose "$($MyInvocation.MyCommand) failed for '$ClusterName': $_"
                Write-Warning "NCC could not be started on $($ClusterName): $($_.Exception.Message)"
                return @{ TaskId = $null; Started = Get-Date; Error = $_.Exception.Message }
            }
            $missingRecipient = $true
        }

        $address = $null
        if (-not $NonInteractive -and -not $State.Asked) {
            $State.Asked = $true
            Write-Host '  No alert email is configured on Prism Central - NCC needs a recipient for its run summary.' -ForegroundColor Yellow
            $address = ([string](Read-Host '  Email address for the NCC summary (Enter = skip NCC)')).Trim()
        }
        if (-not $address) {
            Write-Warning "NCC not started on $($ClusterName): no recipient for the run summary."
            return @{ TaskId = $null; Started = Get-Date; Error = $noRecipient }
        }
        $State.Recipients = @($address -split '[,; ]+' | Where-Object { $_ })
    }

    return @{ TaskId = $null; Started = Get-Date; Error = 'NCC could not be started (no valid recipient for the run summary).' }
}
