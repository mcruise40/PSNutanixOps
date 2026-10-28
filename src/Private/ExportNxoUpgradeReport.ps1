function ExportNxoUpgradeReport {
    <#
    .SYNOPSIS
        Writes the HTML report of an upgrade readiness check for one cluster.

    .DESCRIPTION
        Internal helper for Test-NxoUpgradeReadiness. The report is meant to be attached to the
        change as proof of the pre-check: verdict, run data, all checks with justifications,
        the NCC run, hosts, non-migratable VMs, highest CPU Ready values and acknowledged
        alerts. All values are HTML-encoded. The file name is
        UpgradeReadiness_<cluster>[_<change>]_<yyyyMMdd-HHmm>.html.

    .PARAMETER Folder
        Target folder (must exist).

    .PARAMETER PrismCentral
        Prism Central address.

    .PARAMETER Cluster
        The cluster (clustermgmt cluster object).

    .PARAMETER Verdict
        GO, GO WITH RESERVATIONS or NO-GO.

    .PARAMETER Check
        The check rows.

    .PARAMETER Extra
        Hashtable with Info, Ncc, Hosts, NonMigratable, CpuReady and AckAlerts.

    .PARAMETER ChangeId
        Change or ticket number.

    .PARAMETER Engineer
        Name of the engineer.

    .PARAMETER StartTime
        Start of the CPU evaluation window.

    .PARAMETER EndTime
        End of the CPU evaluation window.

    .EXAMPLE
        ExportNxoUpgradeReport -Folder . -PrismCentral pc01 -Cluster $cl -Verdict GO -Check $checks -Extra $extra -Engineer me -StartTime $s -EndTime $e

    .OUTPUTS
        System.String (path of the report)

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Folder,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $PrismCentral,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]
        $Cluster,

        [Parameter(Mandatory)]
        [ValidateSet('GO', 'GO WITH RESERVATIONS', 'NO-GO')]
        [string]
        $Verdict,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $Check,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]
        $Extra,

        [Parameter()]
        [string]
        $ChangeId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Engineer,

        [Parameter(Mandatory)]
        [datetime]
        $StartTime,

        [Parameter(Mandatory)]
        [datetime]
        $EndTime
    )

    $badge = @{ PASS = 'pass'; WARN = 'warn'; FAIL = 'fail'; INFO = 'info'; SKIPPED = 'skip' }
    $verdictClass = switch ($Verdict) { 'GO' { 'pass' } 'NO-GO' { 'fail' } default { 'warn' } }
    $title = "Upgrade readiness - $($Cluster.name)"
    $sb = [System.Text.StringBuilder]::new()

    [void]$sb.Append(@"
<!doctype html><html lang="en"><head><meta charset="utf-8"><title>$(ConvertToNxoHtml $title)</title>
<style>
body{font-family:Segoe UI,Helvetica,Arial,sans-serif;color:#1f2933;margin:32px;max-width:1100px}
h1{font-size:22px;margin:0 0 4px} h2{font-size:16px;margin:28px 0 8px;border-bottom:1px solid #d9dee3;padding-bottom:4px}
.meta{color:#52606d;font-size:13px} table{border-collapse:collapse;width:100%;font-size:13px}
th,td{text-align:left;padding:6px 8px;border-bottom:1px solid #e4e7eb;vertical-align:top} th{background:#f5f7fa}
.verdict{display:inline-block;margin:16px 0;padding:10px 18px;border-radius:6px;font-size:18px;font-weight:600}
.b{display:inline-block;padding:1px 8px;border-radius:10px;font-size:12px;font-weight:600}
.pass{background:#e3f6e8;color:#1b6b35}.warn{background:#fff3d6;color:#8a5a00}.fail{background:#fde2e1;color:#a61b1b}
.info{background:#e6eefc;color:#1f4fa3}.skip{background:#eceff1;color:#52606d}
.kv td:first-child{width:260px;color:#52606d} .just{font-style:italic}
footer{margin-top:32px;color:#7b8794;font-size:12px}
</style></head><body>
<h1>$(ConvertToNxoHtml $title)</h1>
<div class="meta">Pre-upgrade check via Prism Central v4 API</div>
<div class="verdict $verdictClass">$(ConvertToNxoHtml $Verdict)</div>
<h2>Run</h2><table class="kv">
<tr><td>Cluster</td><td>$(ConvertToNxoHtml $Cluster.name) ($(ConvertToNxoHtml $Cluster.extId))</td></tr>
<tr><td>Prism Central</td><td>$(ConvertToNxoHtml $PrismCentral)</td></tr>
<tr><td>Change</td><td>$(ConvertToNxoHtml $(if ($ChangeId) { $ChangeId } else { '-' }))</td></tr>
<tr><td>Engineer</td><td>$(ConvertToNxoHtml $Engineer)</td></tr>
<tr><td>Executed</td><td>$(ConvertToNxoHtml (Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz'))</td></tr>
<tr><td>CPU evaluation window</td><td>$(ConvertToNxoHtml ('{0:yyyy-MM-dd HH:mm} - {1:yyyy-MM-dd HH:mm} ({2:N0} h)' -f $StartTime, $EndTime, ($EndTime - $StartTime).TotalHours))</td></tr>
"@)
    foreach ($key in @($Extra.Info.Keys)) {
        [void]$sb.Append("<tr><td>$(ConvertToNxoHtml $key)</td><td>$(ConvertToNxoHtml $Extra.Info[$key])</td></tr>")
    }

    [void]$sb.Append('</table><h2>Checks</h2><table><tr><th>Check</th><th>Result</th><th>Value</th><th>Threshold</th><th>Detail / justification</th></tr>')
    foreach ($row in $Check) {
        $justification = if ($row.Justification) { "<div class='just'>Justification: $(ConvertToNxoHtml $row.Justification)</div>" } else { '' }
        [void]$sb.Append("<tr><td>$(ConvertToNxoHtml $row.Check)</td><td><span class='b $($badge[$row.Result])'>$(ConvertToNxoHtml $row.Result)</span></td><td>$(ConvertToNxoHtml $row.Value)</td><td>$(ConvertToNxoHtml $row.Threshold)</td><td>$(ConvertToNxoHtml $row.Detail)$justification</td></tr>")
    }
    [void]$sb.Append('</table>')

    if ($Extra.Ncc) {
        $ncc = $Extra.Ncc
        $nccClass = if ($ncc.Status -eq 'SUCCEEDED') { 'pass' } else { 'warn' }
        [void]$sb.Append("<h2>NCC run</h2><table class='kv'>")
        [void]$sb.Append("<tr><td>Status</td><td><span class='b $nccClass'>$(ConvertToNxoHtml $ncc.Status)</span></td></tr>")
        [void]$sb.Append("<tr><td>Started / completed</td><td>$(ConvertToNxoHtml ('{0} / {1}' -f (FormatNxoDate $ncc.Started 'yyyy-MM-dd HH:mm:ss'), $(if ($ncc.Completed) { FormatNxoDate $ncc.Completed 'yyyy-MM-dd HH:mm:ss' } else { '-' }))) ($(ConvertToNxoHtml $ncc.Duration))</td></tr>")
        [void]$sb.Append("<tr><td>Summary sent to</td><td>$(ConvertToNxoHtml $ncc.Recipients)</td></tr>")
        [void]$sb.Append("<tr><td>Task</td><td>$(ConvertToNxoHtml $ncc.TaskId)</td></tr>")
        if ($ncc.Counts -and $ncc.Counts.Count) {
            $parts = foreach ($key in $ncc.Counts.Keys) {
                $class = switch ($key) {
                    'pass' { 'pass' }
                    'info' { 'info' }
                    'total' { 'skip' }
                    'warn' { if ($ncc.Counts[$key] -gt 0) { 'warn' } else { 'skip' } }
                    default { if ($ncc.Counts[$key] -gt 0) { 'fail' } else { 'skip' } }
                }
                "<span class='b $class'>$(ConvertToNxoHtml $key.ToUpperInvariant()) $(ConvertToNxoHtml $ncc.Counts[$key])</span>"
            }
            $overall = if ($ncc.Overall) { " &nbsp;overall: $(ConvertToNxoHtml $ncc.Overall)" } else { '' }
            [void]$sb.Append("<tr><td>Result</td><td>$($parts -join ' ')$overall</td></tr>")
        }
        foreach ($detail in @($ncc.Details)) { [void]$sb.Append("<tr><td>Task detail</td><td>$(ConvertToNxoHtml $detail)</td></tr>") }
        [void]$sb.Append("<tr><td>Alerts raised during the run</td><td>$(@($ncc.NewAlerts).Count) (Critical/Warning, included in the checks above)</td></tr>")
        [void]$sb.Append('<tr><td>Note</td><td>Counters and the IDs of all non-PASS checks come from the NCC task. The full NCC report with all check outputs is in the summary sent to the recipients above.</td></tr></table>')

        if (@($ncc.Checks).Count) {
            [void]$sb.Append("<h3 style='font-size:14px;margin:16px 0 6px'>Checks not passed</h3><table><tr><th>Result</th><th>Check ID</th><th>Check</th><th>KB</th></tr>")
            foreach ($nccCheck in $ncc.Checks) {
                $class = switch ($nccCheck.Category) { 'FAIL' { 'fail' } 'ERROR' { 'fail' } 'WARN' { 'warn' } 'INFO' { 'info' } default { 'skip' } }
                $kbLinks = @([string]$nccCheck.Kb -split ',\s*' | Where-Object { $_ } | ForEach-Object {
                        if ($_ -match '^https?://') { "<a href='$(ConvertToNxoHtml $_)'>$(ConvertToNxoHtml ($_ -replace '^https?://(www\.)?', ''))</a>" } else { ConvertToNxoHtml $_ }
                    }) -join ', '
                $checkTitle = if ($nccCheck.Title) { $nccCheck.Title } else { '(name not available via API)' }
                [void]$sb.Append("<tr><td><span class='b $class'>$(ConvertToNxoHtml $nccCheck.Category)</span></td><td>$(ConvertToNxoHtml $nccCheck.CheckId)</td><td>$(ConvertToNxoHtml $checkTitle)</td><td>$kbLinks</td></tr>")
            }
            [void]$sb.Append('</table>')
        }
        if (@($ncc.NewAlerts).Count) {
            [void]$sb.Append("<h3 style='font-size:14px;margin:16px 0 6px'>Alerts raised during the NCC run</h3><table><tr><th>Severity</th><th>Title</th><th>Raised</th></tr>")
            foreach ($alert in $ncc.NewAlerts) { [void]$sb.Append("<tr><td>$(ConvertToNxoHtml $alert.Severity)</td><td>$(ConvertToNxoHtml $alert.Title)</td><td>$(ConvertToNxoHtml (FormatNxoDate $alert.Created 'yyyy-MM-dd HH:mm'))</td></tr>") }
            [void]$sb.Append('</table>')
        }
        if (@($ncc.Events).Count) {
            [void]$sb.Append("<h3 style='font-size:14px;margin:16px 0 6px'>Cluster events during the NCC run</h3><table><tr><th>Time</th><th>Type</th><th>Message</th></tr>")
            foreach ($clusterEvent in $ncc.Events) { [void]$sb.Append("<tr><td>$(ConvertToNxoHtml (FormatNxoDate $clusterEvent.Time 'HH:mm:ss'))</td><td>$(ConvertToNxoHtml $clusterEvent.Type)</td><td>$(ConvertToNxoHtml $clusterEvent.Message)</td></tr>") }
            [void]$sb.Append('</table>')
        }
    }

    [void]$sb.Append('<h2>Hosts</h2><table><tr><th>Host</th><th>Type</th><th>Status</th><th>Memory</th><th>Storage</th><th>CPU peak</th><th>Peak at</th><th>GPUs</th></tr>')
    foreach ($hostRow in @($Extra.Hosts)) {
        $state = if ($hostRow.Maintenance) { '{0} / {1}' -f $hostRow.NodeStatus, $hostRow.Maintenance } else { $hostRow.NodeStatus }
        $cpu = if ($null -ne $hostRow.MaxCpuPct) { '{0} %' -f $hostRow.MaxCpuPct } else { 'n/a' }
        $gpu = if ($hostRow.GpuNames) { $hostRow.GpuNames } else { '-' }
        [void]$sb.Append("<tr><td>$(ConvertToNxoHtml $hostRow.Host)</td><td>$(ConvertToNxoHtml $hostRow.Type)</td><td>$(ConvertToNxoHtml $state)</td><td>$(ConvertToNxoHtml (FormatNxoSize -Bytes $hostRow.MemoryBytes -Unit GiB))</td><td>$(ConvertToNxoHtml (FormatNxoSize -Bytes $hostRow.StorageBytes -Unit TiB))</td><td>$(ConvertToNxoHtml $cpu)</td><td>$(ConvertToNxoHtml (FormatNxoDate $hostRow.MaxCpuAt 'yyyy-MM-dd HH:mm'))</td><td>$(ConvertToNxoHtml $gpu)</td></tr>")
    }
    [void]$sb.Append('</table>')

    if (@($Extra.NonMigratable).Count) {
        [void]$sb.Append('<h2>Non-migratable VMs</h2><table><tr><th>VM</th><th>Reason</th><th>Host</th></tr>')
        foreach ($vm in $Extra.NonMigratable) { [void]$sb.Append("<tr><td>$(ConvertToNxoHtml $vm.VM)</td><td>$(ConvertToNxoHtml $vm.Reason)</td><td>$(ConvertToNxoHtml $vm.Host)</td></tr>") }
        [void]$sb.Append('</table>')
    }
    if (@($Extra.CpuReady).Count) {
        [void]$sb.Append('<h2>Highest CPU Ready (top 10)</h2><table><tr><th>VM</th><th>Max CPU Ready</th><th>At</th></tr>')
        foreach ($vm in $Extra.CpuReady) { [void]$sb.Append("<tr><td>$(ConvertToNxoHtml $vm.VM)</td><td>$(ConvertToNxoHtml $vm.MaxReadyPct) %</td><td>$(ConvertToNxoHtml (FormatNxoDate $vm.At 'yyyy-MM-dd HH:mm'))</td></tr>") }
        [void]$sb.Append('</table>')
    }
    if (@($Extra.AckAlerts).Count) {
        [void]$sb.Append('<h2>Acknowledged alerts (information)</h2><table><tr><th>Severity</th><th>Title</th><th>Raised</th><th>Acknowledged by</th></tr>')
        foreach ($alert in $Extra.AckAlerts) { [void]$sb.Append("<tr><td>$(ConvertToNxoHtml $alert.Severity)</td><td>$(ConvertToNxoHtml $alert.Title)</td><td>$(ConvertToNxoHtml (FormatNxoDate $alert.Created 'yyyy-MM-dd HH:mm'))</td><td>$(ConvertToNxoHtml $alert.AcknowledgedBy)</td></tr>") }
        [void]$sb.Append('</table>')
    }

    [void]$sb.Append(@'
<h2>Rating</h2><table class="kv">
<tr><td><span class="b pass">GO</span></td><td>All checks passed.</td></tr>
<tr><td><span class="b warn">GO WITH RESERVATIONS</span></td><td>No resource shortage; each warning carries the engineer's justification.</td></tr>
<tr><td><span class="b fail">NO-GO</span></td><td>Resource shortage or blocking state - do not start the upgrade.</td></tr>
</table>
<footer>Generated by Test-NxoUpgradeReadiness (PSNutanixOps). Projections assume homogeneous hosts and an even redistribution of the load.</footer>
</body></html>
'@)

    $safeCluster = [string]$Cluster.name -replace '[^\w\-]', '_'
    $change = if ($ChangeId) { '_' + ($ChangeId -replace '[^\w\-]', '_') } else { '' }
    $file = Join-Path -Path $Folder -ChildPath ('UpgradeReadiness_{0}{1}_{2:yyyyMMdd-HHmm}.html' -f $safeCluster, $change, $EndTime)
    Set-Content -LiteralPath $file -Value $sb.ToString() -Encoding utf8

    return $file
}
