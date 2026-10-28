function WaitNxoTask {
    <#
    .SYNOPSIS
        Polls a Prism Central task until it finishes or the timeout is reached.

    .DESCRIPTION
        Internal helper. Reads /prism/<revision>/config/tasks/{extId} every -PollSeconds and
        returns the task as soon as its status is SUCCEEDED, FAILED or CANCELED. After
        -TimeoutSeconds the last known task state is returned (status QUEUED or RUNNING), so
        the caller decides how to report a timeout.

    .PARAMETER Connection
        Connection object from the connection store.

    .PARAMETER TaskExtId
        External ID of the task (data.extId of the request that started it).

    .PARAMETER TimeoutSeconds
        Maximum time to wait. Default: 600.

    .PARAMETER PollSeconds
        Interval between two status reads. Default: 5.

    .PARAMETER Activity
        Optional text for Write-Progress.

    .EXAMPLE
        WaitNxoTask -Connection $connection -TaskExtId $response.data.extId -TimeoutSeconds 900

    .OUTPUTS
        PSCustomObject (the task)

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
        [ValidateNotNullOrEmpty()]
        [string]
        $TaskExtId,

        [Parameter()]
        [ValidateRange(1, 86400)]
        [int]
        $TimeoutSeconds = 600,

        [Parameter()]
        [ValidateRange(1, 300)]
        [int]
        $PollSeconds = 5,

        [Parameter()]
        [string]
        $Activity
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $task = $null
    do {
        Start-Sleep -Seconds $PollSeconds
        $task = (InvokeNxoApi -Connection $Connection -Namespace prism -Path "/config/tasks/$TaskExtId").data
        Write-Verbose ('Task {0}: {1} {2} %' -f $TaskExtId, $task.status, $task.progressPercentage)
        if ($task.status -in @('SUCCEEDED', 'FAILED', 'CANCELED')) { break }
        if ($Activity) {
            Write-Progress -Activity $Activity -Status ('{0} {1} %' -f $task.status, $task.progressPercentage) -PercentComplete ([Math]::Min(100, [Math]::Max(0, [int]$task.progressPercentage)))
        }
    } while ((Get-Date) -lt $deadline)

    if ($Activity) { Write-Progress -Activity $Activity -Completed }

    return $task
}
