function ShowNxoStorageComparison {
    <#
    .SYNOPSIS
        Compares the current storage with the state before the recent live cleanup runs.

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup. Reads the storage history and
        compares the current usage of every cluster with the usage measured at the start of the
        first live run with deletions in the last 30 days, next to the space those runs
        expected to free. A deleted recovery point disappears from Prism at once, but its data
        is only freed by the background cleanup (Curator) later, usually within several hours
        to a day; the output explains this.

    .PARAMETER State
        Run state (StorageFile, Stamp, LogFile).

    .PARAMETER Current
        Current measurements (from GetNxoClusterStorage).

    .EXAMPLE
        ShowNxoStorageComparison -State $state -Current $measurements

    .OUTPUTS
        None

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive console wizard: the comparison is a formatted console report.')]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]
        $State,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $Current
    )

    if (-not (Test-Path -LiteralPath $State.StorageFile)) { return }
    try {
        $history = @(Import-Csv -LiteralPath $State.StorageFile -UseCulture)
    } catch {
        Write-Host "  Storage history could not be read: $($_.Exception.Message)" -ForegroundColor Yellow
        return
    }

    $since = [datetime]::UtcNow.AddDays(-30)
    $deletions = @($history | Where-Object { $_.Event -eq 'Deleted' -and $_.RunId -ne $State.Stamp -and (ConvertToNxoUtcTime -Timestamp $_.TimeUtc) -ge $since })
    if (-not $deletions.Count) {
        Write-Host '  No live run with deletions in the last 30 days to compare with.'
        return
    }
    $firstRun = ($deletions | Sort-Object -Property { ConvertToNxoUtcTime -Timestamp $_.TimeUtc } | Select-Object -First 1).RunId
    $baseline = @($history | Where-Object { $_.Event -eq 'Measured' -and $_.RunId -eq $firstRun })
    if (-not $baseline.Count) {
        Write-Host '  The first live run of the last 30 days has no storage measurement to compare with.'
        return
    }

    $runCount = @($deletions | ForEach-Object { $_.RunId } | Select-Object -Unique).Count
    $baselineUtc = ConvertToNxoUtcTime -Timestamp $baseline[0].TimeUtc
    $firstTime = FormatNxoDate -Date $baselineUtc.ToLocalTime()
    $anyDecrease = $false

    Write-Host ''
    if ($runCount -eq 1) {
        Write-Host "Compared with before the live run on ${firstTime}:" -ForegroundColor Cyan
    } else {
        Write-Host "Compared with before the first of $runCount live runs ($firstTime):" -ForegroundColor Cyan
    }

    foreach ($group in ($Current | Group-Object -Property { $_.Pc.Address })) {
        $pcDeletions = @($deletions | Where-Object PrismCentral -EQ $group.Name)
        $deletedCount = [int](($pcDeletions | ForEach-Object { [int]$_.DeletedCount } | Measure-Object -Sum).Sum)
        $expected = ($pcDeletions | Where-Object { $_.FreedAtLeastBytes } | ForEach-Object { [long]$_.FreedAtLeastBytes } | Measure-Object -Sum).Sum
        $line = '  {0} {1}: {2} deleted' -f $group.Group[0].Pc.Label, $group.Name, (FormatNxoCount -Count $deletedCount -Singular 'recovery point')
        if ($expected) { $line += ', expected to free at least {0}' -f (FormatNxoSize -Bytes $expected) }
        Write-Host $line

        foreach ($measurement in $group.Group) {
            $before = $baseline | Where-Object { $_.PrismCentral -eq $group.Name -and $_.ClusterExtId -eq $measurement.ClusterExtId } | Select-Object -First 1
            if (-not $before -or -not $before.UsedBytes -or $null -eq $measurement.UsedBytes) {
                Write-Host "    $($measurement.Cluster): no earlier value"
                continue
            }
            if ($measurement.UsedBytes -lt [long]$before.UsedBytes) { $anyDecrease = $true }
            $text = '    {0}: used storage {1} (now {2})' -f $measurement.Cluster, (FormatNxoChange -Bytes ($measurement.UsedBytes - [long]$before.UsedBytes)), (FormatNxoSize -Bytes $measurement.UsedBytes)
            if ($before.LogicalUsedBytes -and $null -ne $measurement.LogicalUsedBytes) {
                $text += ', logical {0}' -f (FormatNxoChange -Bytes ($measurement.LogicalUsedBytes - [long]$before.LogicalUsedBytes))
            }
            Write-Host $text
            WriteNxoCleanupLog -State $State -Message ('Storage change {0} {1} since {2}: {3}' -f $group.Name, $measurement.Cluster, $firstRun, $text.Trim())
        }
    }

    $elapsed = [datetime]::UtcNow - $baselineUtc
    if ($elapsed.TotalHours -lt 24) {
        $sinceText = if ($elapsed.TotalHours -lt 1) {
            FormatNxoCount -Count ([Math]::Max(1, [int]$elapsed.TotalMinutes)) -Singular 'minute'
        } else {
            FormatNxoCount -Count ([int][Math]::Floor($elapsed.TotalHours)) -Singular 'hour'
        }
        Write-Host "Only $sinceText since the deletion. The cluster frees the space in its background cleanup (Curator)," -ForegroundColor DarkYellow
        Write-Host 'usually within several hours to a day. Until then, a small increase is normal: the clusters keep writing.' -ForegroundColor DarkYellow
    } else {
        Write-Host 'Space is freed by the cluster background cleanup (Curator). Other changes on the cluster count too.'
        if (-not $anyDecrease -and $elapsed.TotalHours -ge 36) {
            Write-Host 'No decrease after 36 hours: check the last Curator scans on a CVM (curator_cli get_last_successful_scans)' -ForegroundColor Yellow
            Write-Host 'and the recycle bin in Prism, or open a case with Nutanix support.' -ForegroundColor Yellow
        }
    }
}
