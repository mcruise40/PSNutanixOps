function GetNxoNccCheckResult {
    <#
    .SYNOPSIS
        Waits for an NCC run and turns its task into a check result.

    .DESCRIPTION
        Internal helper for Test-NxoUpgradeReadiness. The v4 API has no model for NCC check
        results (the per-check summary is only sent by email). The result therefore shows what
        the task itself returns, plus the events of the cluster during the run.

        completionDetails (observed on Prism Central with monitoring v4.2): status, total,
        pass, info, warn, fail, error and detailedSummary = [{ map = { <cat>SdaExtIds =
        "id,id,..." } }] listing the check IDs per non-PASS category.

    .PARAMETER Connection
        Connection object from the connection store.

    .PARAMETER Cluster
        The cluster (clustermgmt cluster object).

    .PARAMETER NccTask
        Hashtable returned by StartNxoNccCheck (TaskId, Started, Error).

    .PARAMETER TimeoutMinutes
        Maximum time since the start of the run.

    .PARAMETER Recipient
        Recipients of the run summary (for the report).

    .PARAMETER CheckCache
        Cache for ResolveNxoNccCheck.

    .EXAMPLE
        GetNxoNccCheckResult -Connection $c -Cluster $cl -NccTask $task -TimeoutMinutes 60 -CheckCache @{}

    .OUTPUTS
        PSCustomObject with Result, Value, Threshold, Detail and Ncc (details for the report)

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
        [ValidateNotNull()]
        [PSCustomObject]
        $Cluster,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]
        $NccTask,

        [Parameter()]
        [ValidateRange(1, 480)]
        [int]
        $TimeoutMinutes = 60,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]
        $Recipient,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]
        $CheckCache
    )

    $threshold = 'Run before upgrade'
    if ($NccTask.Error -or -not $NccTask.TaskId) {
        return [PSCustomObject]@{ Result = 'WARN'; Value = 'Not started'; Threshold = $threshold; Detail = "NCC could not be started via the API: $($NccTask.Error)"; Ncc = $null }
    }

    $remaining = [Math]::Max(1, [int]($TimeoutMinutes - ((Get-Date) - $NccTask.Started).TotalMinutes))
    $task = WaitNxoTask -Connection $Connection -TaskExtId $NccTask.TaskId -TimeoutSeconds ($remaining * 60) -PollSeconds 10 -Activity "NCC on $($Cluster.name)"
    Write-Verbose "NCC task: $($task | ConvertTo-Json -Depth 8 -Compress)"

    $done = ConvertToNxoLocalTime -Timestamp $task.completedTime
    $messages = (@($task.errorMessages | ForEach-Object { $_.message }) + @($task.warnings | ForEach-Object { $_.message }) | Where-Object { $_ }) -join ' '

    $details = @{}
    foreach ($pair in @($task.completionDetails | Where-Object { $_.name })) { $details[$pair.name] = $pair.value }
    $counts = [ordered]@{}
    foreach ($key in @('total', 'pass', 'info', 'warn', 'fail', 'error')) {
        if ($null -ne $details[$key]) { $counts[$key] = [int]$details[$key] }
    }

    $checks = foreach ($entry in @($details['detailedSummary'] | Where-Object { $null -ne $_ })) {
        $map = if ($entry.PSObject.Properties['map']) { $entry.map } else { $entry }
        foreach ($property in @($map.PSObject.Properties | Where-Object { $_.Name -like '*SdaExtIds' })) {
            $category = ($property.Name -replace 'SdaExtIds$').ToUpperInvariant()
            foreach ($id in @([string]$property.Value -split '[,; ]+' | Where-Object { $_ })) {
                $info = ResolveNxoNccCheck -Connection $Connection -CheckId $id -Cache $CheckCache
                [PSCustomObject]@{ Category = $category; CheckId = $id; Title = $info.Title; Kb = $info.Kb }
            }
        }
    }
    $order = @{ FAIL = 0; ERROR = 1; WARN = 2; INFO = 3 }
    $checks = @($checks | Sort-Object -Property @{ Expression = { if ($order.ContainsKey($_.Category)) { $order[$_.Category] } else { 9 } } }, CheckId)

    $taskDetails = @(
        @($task.completionDetails | Where-Object { $_.name -and $_.name -notin @('status', 'total', 'pass', 'info', 'warn', 'fail', 'error', 'detailedSummary') } | ForEach-Object { '{0}: {1}' -f $_.name, $_.value })
        @($task.subSteps | Where-Object { $_.name } | ForEach-Object { "Step: $($_.name)" })
        @($task.warnings | Where-Object { $_.message } | ForEach-Object { "Warning: $($_.message)" })
        @($task.errorMessages | Where-Object { $_.message } | ForEach-Object { "Error: $($_.message)" })
    )

    $end = if ($done) { $done } else { Get-Date }
    $events = @()
    try {
        $events = @(GetNxoClusterEvent -Connection $Connection -ClusterExtId $Cluster.extId -From $NccTask.Started.AddMinutes(-1) -To $end.AddMinutes(1))
    } catch {
        Write-Verbose "Events for $($Cluster.name) not readable: $($_.Exception.Message)"
    }

    $ncc = [ordered]@{
        Status     = $task.status
        Started    = $NccTask.Started
        Completed  = $done
        Duration   = if ($done) { '{0:N0} min' -f ($done - $NccTask.Started).TotalMinutes } else { '-' }
        Recipients = if (@($Recipient).Count) { $Recipient -join ', ' } else { 'Alert email configuration of Prism Central' }
        TaskId     = $NccTask.TaskId
        Details    = $taskDetails
        Overall    = $details['status']
        Counts     = $counts
        Checks     = $checks
        Events     = $events
        NewAlerts  = @()
    }

    switch ($task.status) {
        'SUCCEEDED' {
            $run = 'Run {0:yyyy-MM-dd HH:mm} - {1:HH:mm}.' -f $NccTask.Started, $done
            if ($counts.Count) {
                $value = '{0}/{1} PASS' -f $counts['pass'], $counts['total']
                $bad = @($checks | Where-Object { $_.Category -in @('FAIL', 'ERROR', 'WARN') })
                $badCount = [int]$counts['fail'] + [int]$counts['error'] + [int]$counts['warn']
                $summary = ($counts.Keys | Where-Object { $_ -ne 'total' } | ForEach-Object { '{0} {1}' -f $_.ToUpperInvariant(), $counts[$_] }) -join ', '
                if ($badCount -gt 0) {
                    $list = ($bad | Select-Object -First 8 | ForEach-Object { '{0} {1}{2}' -f $_.Category, $_.CheckId, $(if ($_.Title) { " $($_.Title)" }) }) -join ' | '
                    return [PSCustomObject]@{ Result = 'WARN'; Value = $value; Threshold = 'No FAIL/WARN/ERROR'; Detail = "$run $summary. $list"; Ncc = $ncc }
                }
                return [PSCustomObject]@{ Result = 'PASS'; Value = $value; Threshold = 'No FAIL/WARN/ERROR'; Detail = "$run $summary. Details in the NCC section of the report."; Ncc = $ncc }
            }
            return [PSCustomObject]@{ Result = 'PASS'; Value = 'Completed'; Threshold = $threshold; Detail = "$run No result summary returned by the task; NCC findings are raised as alerts and evaluated with the open alerts. $messages"; Ncc = $ncc }
        }
        'FAILED' {
            $hint = if ($messages -match 'no email configured') { ' -> Run again with -NccReportRecipient <address> or configure the alert email on Prism Central.' } else { '' }
            return [PSCustomObject]@{ Result = 'WARN'; Value = 'Failed'; Threshold = $threshold; Detail = "NCC task failed: $messages$hint"; Ncc = $ncc }
        }
        default {
            return [PSCustomObject]@{ Result = 'WARN'; Value = [string]$task.status; Threshold = $threshold; Detail = "NCC did not finish within $TimeoutMinutes min (task $($NccTask.TaskId))."; Ncc = $ncc }
        }
    }
}
