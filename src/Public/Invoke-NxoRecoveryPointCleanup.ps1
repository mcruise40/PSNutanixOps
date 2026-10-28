function Invoke-NxoRecoveryPointCleanup {
    <#
    .SYNOPSIS
        Guided cleanup of recovery points that are expired or whose VM / volume group no longer
        exists, across one or more Prism Central instances.

    .DESCRIPTION
        Interactive console wizard in five steps:

          1. Connect  - uses the connected Prism Central instances (or the ones named with
                        -Server). Without connection it asks how many Prism Centrals to check,
                        their addresses and logins. Every login is checked first.
          2. Collect  - reads VMs, volume groups and recovery points, and the storage usage of
                        the clusters.
          3. Review   - one row per VM / volume group with the reason, the Prism Central(s), the
                        number of recovery points and the space they hold. Exportable to CSV.
          4. Select   - rows by number (1,4,7-12), by reason (expired / missing) or all.
          5. Delete   - shows the total, asks to type the number of recovery points to confirm,
                        deletes them and writes a log file and a results CSV.

        The mode is shown in every step: [DRY RUN] with -WhatIf (nothing is deleted),
        [STORAGE REPORT] with -StorageReport (only steps 1 and 2), otherwise [LIVE].

        A recovery point is offered for deletion when:
          - VM missing / VG missing: none of its VMs or volume groups exist on any of the Prism
            Centrals checked. All its recovery points are listed, expired or not.
          - VM replaced: like VM missing, but an existing VM has the same name (restored or
            re-created). Check these before deleting.
          - Expired: its expiration time is in the past, but it still exists.
        Recovery points that have not expired and still have their VM are never listed.
        Recovery points with VM template data (VmTemplateRP_...) and secure recovery points are
        never listed either.

        The command does not decide whether a recovery point is still needed: once the
        recovery points of a deleted VM are gone, the VM cannot be restored.

        Recommended order (each run starts with a dry run):
          1. -WhatIf -ExportCsv .\rp-list.csv, select "all", check the list.
          2. Live run, select "expired".
          3. Live run, select "missing 30".
          4. "VM replaced" rows and recently deleted VMs only by row number, after "d <row>".

    .PARAMETER Server
        Prism Central instance(s) to check. Without connection to them, the wizard asks for the
        login. Default: all connected instances; without any connection the wizard asks.

    .PARAMETER Credential
        Login used when the wizard connects (instead of asking per Prism Central).

    .PARAMETER SkipCertificateCheck
        Used when the wizard connects: do not validate the TLS certificate.

    .PARAMETER ExportCsv
        Writes the list of step 3 to this CSV file (one line per recovery point).

    .PARAMETER LogDirectory
        Folder for the log, the results CSV and the storage history. Default: current folder.
        Use the same folder for every run, so the storage history can be compared.

    .PARAMETER StorageReport
        Only connects, reads the storage of the clusters and compares it with the usage before
        the last live runs. Nothing is deleted. Run it a day after a live run.

    .PARAMETER TimeoutSeconds
        Maximum time to wait for one deletion task. Default: 600.

    .PARAMETER BatchSize
        Number of deletions started at the same time. Default: 5. Lower it (e.g. 2) if Prism
        Central keeps reporting its API rate limit.

    .EXAMPLE
        Connect-NxoPrismCentral -Server pc-a.example.local, pc-b.example.local -Credential $cred -SkipCertificateCheck
        Invoke-NxoRecoveryPointCleanup -WhatIf -ExportCsv .\rp-list.csv

        Dry run over both Prism Central instances, exporting the list.

    .EXAMPLE
        Invoke-NxoRecoveryPointCleanup

        Live run; asks for the Prism Centrals if none is connected.

    .EXAMPLE
        Invoke-NxoRecoveryPointCleanup -StorageReport

        A day after a live run: shows how much the used storage changed since the deletion.

    .INPUTS
        None

    .OUTPUTS
        None. Log file, results CSV and storage history are written to -LogDirectory.

    .NOTES
        - Include every Prism Central that replicates recovery points with the others;
          otherwise a replicated recovery point can wrongly look like its VM is missing.
        - A VM or volume group is only reported missing if every Prism Central answers
          "not found" when it is looked up by ID; other errors count as unverified.
        - Space: totalExclusiveUsageBytes (API v4.2 and later). Totals are a lower bound. The
          space is freed by the cluster background cleanup (Curator), usually within several
          hours to a day.
        - Deletion is irreversible. Run with -WhatIf for a dry run.

    .LINK
        Get-NxoRecoveryPoint
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive console wizard: all guidance, tables and prompts are written to the console by design.')]
    param (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [Alias('PrismCentral')]
        [string[]]
        $Server,

        [Parameter()]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty,

        [Parameter()]
        [switch]
        $SkipCertificateCheck,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $ExportCsv,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $LogDirectory = (Get-Location).Path,

        [Parameter()]
        [switch]
        $StorageReport,

        [Parameter()]
        [ValidateRange(30, 7200)]
        [int]
        $TimeoutSeconds = 600,

        [Parameter()]
        [ValidateRange(1, 50)]
        [int]
        $BatchSize = 5
    )

    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        $null = New-Item -ItemType Directory -Path $LogDirectory -WhatIf:$false -Confirm:$false
    }
    $dryRun = [bool]$WhatIfPreference
    $mode = if ($StorageReport) { 'STORAGE REPORT' } elseif ($dryRun) { 'DRY RUN' } else { 'LIVE' }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $logFolder = (Resolve-Path -LiteralPath $LogDirectory).Path
    $suffix = @{ 'STORAGE REPORT' = 'REPORT'; 'DRY RUN' = 'DRYRUN'; 'LIVE' = 'LIVE' }[$mode]
    $state = @{
        Mode        = $mode
        DryRun      = $dryRun
        TotalSteps  = if ($StorageReport) { 2 } else { 5 }
        Stamp       = $stamp
        LogFile     = Join-Path -Path $logFolder -ChildPath "RecoveryPointCleanup_$($stamp)_$suffix.log"
        StorageFile = Join-Path -Path $logFolder -ChildPath 'RecoveryPointCleanup_storage-history.csv'
        Results     = [System.Collections.Generic.List[object]]::new()
    }

    Write-Host ''
    Write-Host 'Nutanix recovery point cleanup' -ForegroundColor Cyan
    Write-Host 'Finds recovery points that are expired or whose VM / volume group no longer exists,'
    Write-Host 'and deletes the ones you select.'
    Write-Host ''
    if ($StorageReport) {
        Write-Host ' STORAGE REPORT: only reads the storage usage of the clusters, nothing is deleted. ' -ForegroundColor Black -BackgroundColor Cyan
    } elseif ($dryRun) {
        Write-Host ' DRY RUN (-WhatIf): nothing will be deleted. ' -ForegroundColor Black -BackgroundColor Yellow
        Write-Host 'All steps run as usual; step 5 only lists what would be deleted.'
    } else {
        Write-Host ' LIVE RUN: the recovery points you select will be deleted permanently. ' -ForegroundColor White -BackgroundColor DarkRed
        Write-Host 'Nothing is deleted before you confirm in step 4. For a dry run, quit and start again with -WhatIf.'
    }
    Write-Host "Log: $($state.LogFile)"
    WriteNxoCleanupLog -State $state -Message ('Started by {0} on {1}, mode {2}' -f [Environment]::UserName, [Environment]::MachineName, $mode)

    try {
        #region Step 1: connect
        WriteNxoCleanupStep -State $state -Number 1 -Title 'Connect to Prism Central'

        $store = GetNxoConnectionStore
        $connectParam = @{ SkipCertificateCheck = $SkipCertificateCheck; ErrorAction = 'Stop' }
        if ($Server) {
            $addresses = @($Server | ForEach-Object { ConvertToNxoServerName -Server $_ } | Select-Object -Unique)
        } elseif ($store.Count) {
            $addresses = @($store.Keys)
        } else {
            Write-Host 'Include every Prism Central that replicates recovery points with the others.'
            Write-Host 'Otherwise a replicated recovery point can wrongly look like its VM is missing.'
            $count = ReadNxoNumber -Prompt 'How many Prism Centrals do you want to check?' -Min 1 -Max 20
            $addresses = @(for ($index = 1; $index -le $count; $index++) {
                    ConvertToNxoServerName -Server (ReadNxoText -Prompt "  Address of Prism Central $index (IP or FQDN)")
                }) | Select-Object -Unique
            $addresses = @($addresses)
        }

        $pcs = [System.Collections.Generic.List[object]]::new()
        $previous = $null
        foreach ($address in $addresses) {
            $pcs.Add([PSCustomObject]@{ Label = "PC$($pcs.Count + 1)"; Address = $address; Connection = $null; AskLogin = $false; EsxiListOk = $false; VgListOk = $false })
        }

        Write-Host ''
        Write-Host 'Checking logins...'
        $pending = @($pcs)
        while ($pending.Count) {
            $failed = @()
            foreach ($pc in $pending) {
                $problem = $null
                if (-not $store.Contains($pc.Address)) {
                    # -Credential is used once; after a failed login the wizard asks.
                    $credentialToUse = if ($pc.AskLogin) { [System.Management.Automation.PSCredential]::Empty } else { $Credential }
                    if ($credentialToUse -eq [System.Management.Automation.PSCredential]::Empty) {
                        if ($previous -and (ReadNxoYesNo -Prompt "  Use the same login ($($previous.UserName)) for $($pc.Address)?")) {
                            $credentialToUse = $previous
                        } else {
                            $credentialToUse = Get-Credential -Message "Login for Prism Central $($pc.Address)"
                        }
                    }
                    $previous = $credentialToUse
                    try {
                        $null = Connect-NxoPrismCentral -Server $pc.Address -Credential $credentialToUse @connectParam
                    } catch {
                        $problem = $_.Exception.Message
                    }
                }
                if (-not $problem) {
                    $pc.Connection = $store[$pc.Address]
                    $problem = TestNxoCleanupAccess -Connection $pc.Connection
                }
                if ($problem) {
                    Write-Host ('  [FAILED] {0} {1}: {2}' -f $pc.Label, $pc.Address, $problem) -ForegroundColor Red
                    WriteNxoCleanupLog -State $state -Message ('Login check failed for {0}: {1}' -f $pc.Address, $problem) -Level WARN
                    $failed += $pc
                } else {
                    Write-Host ('  [OK]     {0} {1} (user {2})' -f $pc.Label, $pc.Address, $pc.Connection.Credential.UserName) -ForegroundColor Green
                    WriteNxoCleanupLog -State $state -Message ('Login OK for {0} as {1}' -f $pc.Address, $pc.Connection.Credential.UserName)
                }
            }
            foreach ($pc in $failed) {
                $choice = ReadNxoChoice -Prompt "  $($pc.Label) $($pc.Address): [L]ogin again, change [A]ddress, or [Q]uit" -Allowed L, A, Q
                if ($choice -eq 'Q') { throw [System.OperationCanceledException]::new('Cancelled.') }
                # Drop the connection that did not work, so the next round logs in again.
                if ($store.Contains($pc.Address)) { $store.Remove($pc.Address) }
                if ($choice -eq 'A') { $pc.Address = ConvertToNxoServerName -Server (ReadNxoText -Prompt '  New address') }
                $pc.AskLogin = $true
                $previous = $null
            }
            $pending = $failed
        }

        if ($StorageReport) {
            WriteNxoCleanupStep -State $state -Number 2 -Title 'Storage'
            InvokeNxoStorageCheck -State $state -Pc $pcs.ToArray()
            Write-Host ''
            Write-Host "Storage history: $($state.StorageFile)"
            Write-Host "Log: $($state.LogFile)"
            WriteNxoCleanupLog -State $state -Message 'Storage report finished.'
            return
        }
        #endregion

        #region Step 2: collect
        WriteNxoCleanupStep -State $state -Number 2 -Title 'Collect VMs, volume groups and recovery points'
        $vmIndex = @{}   # VM extId -> name, all Prism Centrals combined
        $vgIndex = @{}
        $entries = [System.Collections.Generic.List[object]]::new()

        foreach ($pc in $pcs) {
            try {
                $ahvVms = @(GetNxoPagedList -Connection $pc.Connection -Namespace vmm -Path '/ahv/config/vms' -Activity "$($pc.Label): reading AHV VMs")
                $recoveryPoints = @(GetNxoPagedList -Connection $pc.Connection -Namespace dataprotection -Path '/config/recovery-points' -Activity "$($pc.Label): reading recovery points")
            } catch {
                throw [System.OperationCanceledException]::new(('Could not read from {0}: {1}' -f $pc.Address, $_.Exception.Message))
            }
            foreach ($vm in $ahvVms) { if ($vm.extId) { $vmIndex[$vm.extId] = $vm.name } }

            $esxiVms = @()
            try {
                $esxiVms = @(GetNxoPagedList -Connection $pc.Connection -Namespace vmm -Path '/esxi/config/vms' -Activity "$($pc.Label): reading ESXi VMs")
                $pc.EsxiListOk = $true
                foreach ($vm in $esxiVms) { if ($vm.extId) { $vmIndex[$vm.extId] = $vm.name } }
            } catch {
                $message = "{0}: ESXi VMs could not be read ({1}). Recovery points of ESXi VMs are not offered as 'VM missing'." -f $pc.Label, $_.Exception.Message
                Write-Host "  $message" -ForegroundColor Yellow
                WriteNxoCleanupLog -State $state -Message $message -Level WARN
            }

            $volumeGroups = @()
            try {
                $volumeGroups = @(GetNxoPagedList -Connection $pc.Connection -Namespace volumes -Path '/config/volume-groups' -Activity "$($pc.Label): reading volume groups")
                $pc.VgListOk = $true
                foreach ($volumeGroup in $volumeGroups) { if ($volumeGroup.extId) { $vgIndex[$volumeGroup.extId] = $volumeGroup.name } }
            } catch {
                $message = '{0}: volume groups could not be read ({1}). Their recovery points are only offered if expired.' -f $pc.Label, $_.Exception.Message
                Write-Host "  $message" -ForegroundColor Yellow
                WriteNxoCleanupLog -State $state -Message $message -Level WARN
            }

            foreach ($recoveryPoint in $recoveryPoints) { $entries.Add([PSCustomObject]@{ Pc = $pc; Rp = $recoveryPoint }) }
            $summary = '{0} {1}: {2}, {3}, {4}' -f $pc.Label, $pc.Address, (FormatNxoCount -Count ($ahvVms.Count + $esxiVms.Count) -Singular 'VM'),
            (FormatNxoCount -Count $volumeGroups.Count -Singular 'volume group'), (FormatNxoCount -Count $recoveryPoints.Count -Singular 'recovery point')
            Write-Host "  $summary"
            WriteNxoCleanupLog -State $state -Message $summary
        }
        InvokeNxoStorageCheck -State $state -Pc $pcs.ToArray()
        #endregion

        #region Step 3: review
        WriteNxoCleanupStep -State $state -Number 3 -Title 'Review'

        # VMs / volume groups referenced by recovery points but not in any inventory: double-check each by ID.
        $vmHypervisor = @{}
        $unknownVmIds = [System.Collections.Generic.HashSet[string]]::new()
        $unknownVgIds = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($entry in $entries) {
            foreach ($vmRecoveryPoint in @($entry.Rp.vmRecoveryPoints | Where-Object { $_ -and $_.vmExtId })) {
                if ($vmRecoveryPoint.hypervisorType) { $vmHypervisor[$vmRecoveryPoint.vmExtId] = [string]$vmRecoveryPoint.hypervisorType }
                if (-not $vmIndex.ContainsKey($vmRecoveryPoint.vmExtId)) { [void]$unknownVmIds.Add($vmRecoveryPoint.vmExtId) }
            }
            foreach ($vgRecoveryPoint in @($entry.Rp.volumeGroupRecoveryPoints | Where-Object { $_ -and $_.volumeGroupExtId })) {
                if (-not $vgIndex.ContainsKey($vgRecoveryPoint.volumeGroupExtId)) { [void]$unknownVgIds.Add($vgRecoveryPoint.volumeGroupExtId) }
            }
        }
        $entityState = @{}
        $checked = 0
        $toCheck = $unknownVmIds.Count + $unknownVgIds.Count
        foreach ($id in $unknownVmIds) {
            $checked++
            Write-Progress -Activity 'Checking missing VMs and VGs' -Status "$checked of $toCheck" -PercentComplete (100 * $checked / $toCheck)
            $entityState[$id] = GetNxoEntityState -Pc $pcs.ToArray() -Kind Vm -ExtId $id -HypervisorType $vmHypervisor[$id]
        }
        foreach ($id in $unknownVgIds) {
            $checked++
            Write-Progress -Activity 'Checking missing VMs and VGs' -Status "$checked of $toCheck" -PercentComplete (100 * $checked / $toCheck)
            $entityState[$id] = GetNxoEntityState -Pc $pcs.ToArray() -Kind VolumeGroup -ExtId $id
        }
        Write-Progress -Activity 'Checking missing VMs and VGs' -Completed
        foreach ($id in @($entityState.Keys)) {
            if ($entityState[$id] -eq 'Exists') { WriteNxoCleanupLog -State $state -Message "Found by ID but not in the list: $id" -Level WARN }
        }

        # Classify every recovery point.
        $nowUtc = [datetime]::UtcNow
        $candidates = [System.Collections.Generic.List[object]]::new()
        $skipped = [ordered]@{ Secure = 0; Template = 0; Unverified = 0; PartlyMissing = 0; Empty = 0 }
        foreach ($entry in $entries) {
            $recoveryPoint = $entry.Rp
            $vmIds = @(@($recoveryPoint.vmRecoveryPoints) | ForEach-Object { $_.vmExtId } | Where-Object { $_ } | Select-Object -Unique)
            $vgIds = @(@($recoveryPoint.volumeGroupRecoveryPoints) | ForEach-Object { $_.volumeGroupExtId } | Where-Object { $_ } | Select-Object -Unique)
            if (-not ($vmIds.Count + $vgIds.Count)) { $skipped.Empty++; continue }

            $states = @(
                foreach ($id in $vmIds) { if ($vmIndex.ContainsKey($id)) { 'Exists' } else { $entityState[$id] } }
                foreach ($id in $vgIds) { if ($vgIndex.ContainsKey($id)) { 'Exists' } else { $entityState[$id] } }
            )
            $expiresUtc = ConvertToNxoUtcTime -Timestamp $recoveryPoint.expirationTime
            $isExpired = $null -ne $expiresUtc -and $expiresUtc -lt $nowUtc

            if (-not ($states | Where-Object { $_ -ne 'Missing' })) {
                $reason = if ($vmIds.Count) { 'VM missing' } else { 'VG missing' }
            } elseif ($isExpired) {
                $reason = 'Expired'
            } else {
                if ($states -contains 'Unverified' -and $states -notcontains 'Exists') { $skipped.Unverified++ }
                elseif ($states -contains 'Missing') { $skipped.PartlyMissing++ }
                continue
            }
            if ([string]$recoveryPoint.name -like 'VmTemplateRP_*') {
                # Holds a VM template version; its "VM" is not a normal VM, so it always looks missing.
                $skipped.Template++
                WriteNxoCleanupLog -State $state -Message ('Skipped VM template recovery point {0} ({1}) on {2}' -f $recoveryPoint.name, $recoveryPoint.extId, $entry.Pc.Address) -Level WARN
                continue
            }
            if ($recoveryPoint.isSecure) {
                $skipped.Secure++
                WriteNxoCleanupLog -State $state -Message ('Skipped secure recovery point {0} ({1}) on {2}' -f $recoveryPoint.name, $recoveryPoint.extId, $entry.Pc.Address) -Level WARN
                continue
            }

            $candidates.Add([PSCustomObject]@{
                    Reason             = $reason
                    Type               = if ($vmIds.Count -and $vgIds.Count) { 'VM+VG' } elseif ($vmIds.Count) { 'VM' } else { 'VG' }
                    GroupKey           = $reason + '|' + ((@($vmIds) + @($vgIds) | Sort-Object) -join ',')
                    Name               = ''
                    VmIds              = $vmIds
                    VgIds              = $vgIds
                    Pc                 = $entry.Pc
                    Rp                 = $recoveryPoint
                    RpExtId            = $recoveryPoint.extId
                    RpName             = $recoveryPoint.name
                    LocationAgnosticId = $recoveryPoint.locationAgnosticId
                    CreatedUtc         = ConvertToNxoUtcTime -Timestamp $recoveryPoint.creationTime
                    ExpiresUtc         = $expiresUtc
                    SizeBytes          = GetNxoRecoveryPointSize -RecoveryPoint $recoveryPoint
                })
        }

        if (-not $candidates.Count) {
            Write-Host 'Nothing to clean up: no expired recovery points and none without a VM or volume group.' -ForegroundColor Green
            WriteNxoCleanupLog -State $state -Message 'Nothing to clean up.'
            Write-Host "Log: $($state.LogFile)"
            return
        }

        # Names: from the inventory, or for deleted VMs from the VM configuration in the recovery point.
        $deletedVmNames = @{}
        $resolveFrom = [ordered]@{}
        foreach ($candidate in $candidates) {
            foreach ($id in $candidate.VmIds) {
                if (-not $vmIndex.ContainsKey($id) -and -not $resolveFrom.Contains($id)) { $resolveFrom[$id] = $candidate }
            }
        }
        $resolved = 0
        foreach ($id in @($resolveFrom.Keys)) {
            $resolved++
            Write-Progress -Activity 'Reading names of deleted VMs' -Status "$resolved of $($resolveFrom.Count)" -PercentComplete (100 * $resolved / $resolveFrom.Count)
            $deletedVmNames[$id] = ResolveNxoDeletedVmName -Connection $resolveFrom[$id].Pc.Connection -RecoveryPoint $resolveFrom[$id].Rp -VmExtId $id
        }
        Write-Progress -Activity 'Reading names of deleted VMs' -Completed
        foreach ($candidate in $candidates) {
            $names = @(
                foreach ($id in $candidate.VmIds) { if ($vmIndex.ContainsKey($id)) { $vmIndex[$id] } else { $deletedVmNames[$id] } }
                foreach ($id in $candidate.VgIds) { if ($vgIndex.ContainsKey($id) -and $vgIndex[$id]) { $vgIndex[$id] } else { 'volume group {0}' -f (GetNxoShortId -Id $id) } }
            )
            $candidate.Name = $names -join ', '
        }

        # A deleted VM whose name is used by an existing VM was probably restored or re-created.
        $liveVmNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($name in $vmIndex.Values) { if ($name) { [void]$liveVmNames.Add($name) } }
        foreach ($candidate in $candidates) {
            if ($candidate.Reason -ne 'VM missing') { continue }
            if (@($candidate.VmIds | Where-Object { $liveVmNames.Contains([string]$deletedVmNames[$_]) }).Count) {
                $candidate.Reason = 'VM replaced'
                $candidate.GroupKey = 'VM replaced|' + ($candidate.GroupKey -replace '^[^|]*\|')
            }
        }

        # Sizes missing from the list response: try single recovery points (stop if the API never returns one).
        $noSize = @($candidates | Where-Object { $null -eq $_.SizeBytes })
        $tried = 0
        $found = 0
        foreach ($candidate in $noSize) {
            if ($tried -ge 3 -and $found -eq 0) { break }
            $tried++
            Write-Progress -Activity 'Reading sizes' -Status "$tried of $($noSize.Count)" -PercentComplete (100 * $tried / $noSize.Count)
            try {
                $size = GetNxoRecoveryPointSize -RecoveryPoint (InvokeNxoApi -Connection $candidate.Pc.Connection -Namespace dataprotection -Path "/config/recovery-points/$($candidate.RpExtId)").data
                if ($null -ne $size) { $candidate.SizeBytes = $size; $found++ }
            } catch {
                Write-Verbose "No size for recovery point $($candidate.RpExtId): $($_.Exception.Message)"
            }
        }
        Write-Progress -Activity 'Reading sizes' -Completed

        # Newest recovery point of each VM / volume group over all recovery points (also ones that are not
        # listed), so "missing 30" judges a deleted VM by its last recovery point, not only by its row.
        $newestById = @{}
        foreach ($entry in $entries) {
            $created = ConvertToNxoUtcTime -Timestamp $entry.Rp.creationTime
            if ($null -eq $created) { continue }
            $ids = @(@($entry.Rp.vmRecoveryPoints) | ForEach-Object { $_.vmExtId }) + @(@($entry.Rp.volumeGroupRecoveryPoints) | ForEach-Object { $_.volumeGroupExtId })
            foreach ($id in ($ids | Where-Object { $_ })) {
                if (-not $newestById.ContainsKey($id) -or $created -gt $newestById[$id]) { $newestById[$id] = $created }
            }
        }

        # One row per VM / volume group and reason; missing VMs first.
        $reasonOrder = @{ 'VM missing' = 0; 'VG missing' = 1; 'VM replaced' = 2; 'Expired' = 3 }
        $rows = @($candidates | Group-Object -Property GroupKey | ForEach-Object {
                $items = @($_.Group)
                $known = @($items | Where-Object { $null -ne $_.SizeBytes })
                $expiries = @($items | Where-Object { $_.ExpiresUtc } | ForEach-Object { $_.ExpiresUtc } | Sort-Object)
                $createdTimes = @($items | Where-Object { $_.CreatedUtc } | ForEach-Object { $_.CreatedUtc } | Sort-Object)
                $entityNewest = @(@($items[0].VmIds) + @($items[0].VgIds) | Where-Object { $_ } | ForEach-Object { $newestById[$_] } | Where-Object { $_ } | Sort-Object)
                [PSCustomObject]@{
                    Row             = 0
                    Reason          = $items[0].Reason
                    Name            = $items[0].Name
                    Pcs             = (@($items | ForEach-Object { $_.Pc.Label } | Sort-Object -Unique) -join ',')
                    Count           = $items.Count
                    OldestUtc       = $createdTimes | Select-Object -First 1
                    NewestUtc       = $createdTimes | Select-Object -Last 1
                    EntityNewestUtc = if ($entityNewest.Count) { $entityNewest[-1] } else { $createdTimes | Select-Object -Last 1 }
                    OverdueDays     = if ($expiries.Count) { [int][Math]::Floor(($nowUtc - $expiries[0]).TotalDays) } else { 0 }
                    SizeBytes       = if ($known.Count) { [long]($known | Measure-Object -Property SizeBytes -Sum).Sum } else { $null }
                    UnknownSize     = $items.Count - $known.Count
                    Items           = $items
                }
            } | Sort-Object -Property @{ Expression = { $reasonOrder[$_.Reason] } }, Name)
        for ($index = 0; $index -lt $rows.Count; $index++) { $rows[$index].Row = $index + 1 }

        ShowNxoCleanupOverview -Row $rows -Candidate $candidates.ToArray() -Pc $pcs.ToArray()
        $notListed = @(
            if ($skipped.Secure) { '{0} - deleting needs an approval in Prism Central' -f (FormatNxoCount -Count $skipped.Secure -Singular 'secure recovery point') }
            if ($skipped.Template) { '{0} with VM template data (VmTemplateRP_...) - deleting would break the template' -f (FormatNxoCount -Count $skipped.Template -Singular 'recovery point') }
            if ($skipped.Unverified) { '{0} whose VM / volume group could not be verified (for example missing permissions)' -f (FormatNxoCount -Count $skipped.Unverified -Singular 'recovery point') }
            if ($skipped.PartlyMissing) { '{0} with several VMs of which only some are missing' -f (FormatNxoCount -Count $skipped.PartlyMissing -Singular 'recovery point') }
            if ($skipped.Empty) { '{0} without VM or volume group' -f (FormatNxoCount -Count $skipped.Empty -Singular 'recovery point') }
        )
        if ($notListed.Count) {
            Write-Host 'Not listed:' -ForegroundColor Yellow
            foreach ($line in $notListed) { Write-Host "  $line" -ForegroundColor Yellow }
        }
        WriteNxoCleanupLog -State $state -Message ('Found {0} recovery points in {1} rows; skipped: {2}' -f $candidates.Count, $rows.Count, (($skipped.GetEnumerator() | ForEach-Object { '{0}={1}' -f $_.Key, $_.Value }) -join ', '))

        if ($ExportCsv) { ExportNxoCleanupCandidate -State $state -Row $rows -Path $ExportCsv }
        #endregion

        #region Step 4: select
        WriteNxoCleanupStep -State $state -Number 4 -Title 'Select'
        ShowNxoCleanupHelp

        # "continue" inside a switch only leaves the switch, so the loop is labeled.
        :selection while ($true) {
            $answer = ([string](Read-Host -Prompt 'Selection')).Trim()
            $selectedRows = $null
            switch -Regex ($answer) {
                '^(q|quit|exit)$' { throw [System.OperationCanceledException]::new('Cancelled.') }
                '^(l|list)$' { ShowNxoCleanupOverview -Row $rows -Candidate $candidates.ToArray() -Pc $pcs.ToArray(); continue selection }
                '^(h|help|\?)$' { ShowNxoCleanupHelp; continue selection }
                '^csv$' {
                    $path = ReadNxoText -Prompt 'CSV file' -Default ($state.LogFile -replace '\.log$', '_list.csv')
                    try { ExportNxoCleanupCandidate -State $state -Row $rows -Path $path } catch { Write-Host "Export failed: $($_.Exception.Message)" -ForegroundColor Red }
                    continue selection
                }
                '^d\s*(\d+)$' {
                    $number = [int]$Matches[1]
                    if ($number -ge 1 -and $number -le $rows.Count) { ShowNxoCleanupRowDetail -Row $rows[$number - 1] }
                    else { Write-Host "There is no row $number." -ForegroundColor Yellow }
                    continue selection
                }
                '^all$' { $selectedRows = $rows }
                '^expired$' { $selectedRows = @($rows | Where-Object Reason -EQ 'Expired') }
                '^missing(?:\s+(\d+))?$' {
                    # "missing 30": leave out VMs / volume groups that still had a recovery point in the last 30 days,
                    # counting all their recovery points (EntityNewestUtc), not only the ones in this row.
                    $minDays = if ($Matches[1]) { [int]$Matches[1] } else { 0 }
                    $selectedRows = @($rows | Where-Object {
                            $_.Reason -like '*missing' -and ($minDays -eq 0 -or (
                                    $_.NewestUtc -and ($nowUtc - $_.NewestUtc).TotalDays -ge $minDays -and
                                    $_.EntityNewestUtc -and ($nowUtc - $_.EntityNewestUtc).TotalDays -ge $minDays))
                        })
                }
                default {
                    $numbers = @(ConvertFromNxoRowSelection -Text $answer -Max $rows.Count)
                    if ($numbers.Count) { $selectedRows = @($numbers | ForEach-Object { $rows[$_ - 1] }) }
                }
            }
            if ($null -eq $selectedRows) {
                if ($answer) { Write-Host 'Not understood. Use for example 1,4,7-12 or all, or type help.' -ForegroundColor Yellow }
                continue
            }
            $selectedRows = @($selectedRows)
            if (-not $selectedRows.Count) { Write-Host 'No rows match.' -ForegroundColor Yellow; continue }

            $selectedItems = @($selectedRows | ForEach-Object { $_.Items })
            Write-Host ''
            Write-Host 'Selected:' -ForegroundColor Cyan
            ShowNxoCleanupRow -Row $selectedRows
            foreach ($group in ($selectedItems | Group-Object -Property { $_.Pc.Label } | Sort-Object -Property Name)) {
                $groupPc = $group.Group[0].Pc
                Write-Host ('  {0} {1}: {2}, space {3}' -f $groupPc.Label, $groupPc.Address, (FormatNxoCount -Count $group.Count -Singular 'recovery point'), (FormatNxoTotal -Item $group.Group))
            }
            Write-Host ('Total: {0}, space freed: {1}' -f (FormatNxoCount -Count $selectedItems.Count -Singular 'recovery point'), (FormatNxoTotal -Item $selectedItems)) -ForegroundColor Cyan
            $notExpired = @($selectedItems | Where-Object { $null -eq $_.ExpiresUtc -or $_.ExpiresUtc -gt $nowUtc })
            if ($notExpired.Count) {
                Write-Host ('Not expired yet: {0}. Their VM / volume group no longer exists and cannot be restored after deleting them.' -f (FormatNxoCount -Count $notExpired.Count -Singular 'recovery point')) -ForegroundColor Yellow
            }
            $replacedRows = @($selectedRows | Where-Object Reason -EQ 'VM replaced')
            if ($replacedRows.Count) {
                Write-Host ('Selected rows with reason VM replaced: {0}. Another VM has the same name; check with d <row> first.' -f ($replacedRows.Row -join ', ')) -ForegroundColor Yellow
            }
            Write-Host 'The space shows up as free once the cluster background cleanup has run (usually several hours to a day).'
            Write-Host ''

            if ($dryRun) {
                if (ReadNxoYesNo -Prompt 'DRY RUN: list what would be deleted (nothing is deleted)?') { break selection }
            } else {
                WriteNxoCleanupStep -State $state
                Write-Host ''
                $confirm = ([string](Read-Host -Prompt ('Type {0} to delete {1} permanently, or press Enter to go back' -f $selectedItems.Count, (FormatNxoCount -Count $selectedItems.Count -Singular 'recovery point')))).Trim()
                if ($confirm -eq [string]$selectedItems.Count) { break selection }
                Write-Host 'Not confirmed. Back to the selection.' -ForegroundColor Yellow
            }
        }
        WriteNxoCleanupLog -State $state -Message ('Selected rows: {0}' -f (($selectedRows | ForEach-Object { '{0} {1} ({2})' -f $_.Row, $_.Name, $_.Reason }) -join '; '))
        $action = if ($dryRun) { 'Dry run for' } else { 'Confirmed deletion of' }
        WriteNxoCleanupLog -State $state -Message ('{0} {1} recovery points, space {2}' -f $action, $selectedItems.Count, (FormatNxoTotal -Item $selectedItems))
        #endregion
    } catch [System.OperationCanceledException] {
        # Only raised before anything was deleted.
        Write-Host ''
        Write-Host "$($_.Exception.Message) Nothing was deleted." -ForegroundColor Yellow
        WriteNxoCleanupLog -State $state -Message "$($_.Exception.Message) Nothing was deleted." -Level WARN
        Write-Host "Log: $($state.LogFile)"
        return
    }

    #region Step 5: delete
    $stepTitle = if ($dryRun) { 'Delete (simulated, nothing is deleted)' } else { 'Delete' }
    WriteNxoCleanupStep -State $state -Number 5 -Title $stepTitle
    $queue = @($selectedItems | Sort-Object -Property { $_.Pc.Label }, Name, CreatedUtc)
    $finishedCount = 0
    $running = [System.Collections.Generic.List[object]]::new()
    $resultsCsv = $state.LogFile -replace '\.log$', '_results.csv'
    $completed = $false
    try {
        for ($start = 0; $start -lt $queue.Count; $start += $BatchSize) {
            $batch = $queue[$start..([Math]::Min($start + $BatchSize, $queue.Count) - 1)]
            $running.Clear()

            foreach ($item in $batch) {
                $target = '{0} / {1} on {2} ({3})' -f $item.Name, $item.RpName, $item.Pc.Address, $item.RpExtId
                if (-not $PSCmdlet.ShouldProcess($target, 'Delete recovery point')) {
                    # Dry run (-WhatIf), or "No" / "No to All" in a -Confirm prompt of a live run.
                    if ($dryRun) { AddNxoCleanupResult -State $state -Item $item -Status 'Not deleted (dry run)' }
                    else { AddNxoCleanupResult -State $state -Item $item -Status 'Skipped (not confirmed)' -Message 'answered No in the confirmation prompt' }
                    $finishedCount++
                    continue
                }
                try {
                    $response = InvokeNxoApi -Connection $item.Pc.Connection -Namespace dataprotection -Method DELETE -Path "/config/recovery-points/$($item.RpExtId)"
                    $taskId = $response.data.extId
                    if ($taskId) {
                        $running.Add([PSCustomObject]@{ Item = $item; TaskId = $taskId; Started = [datetime]::UtcNow; PollErrors = 0 })
                    } else {
                        AddNxoCleanupResult -State $state -Item $item -Status Failed -Message 'No task ID returned'
                        $finishedCount++
                    }
                } catch {
                    if ((GetNxoStatusCode -Exception $_.Exception) -eq 404) {
                        AddNxoCleanupResult -State $state -Item $item -Status 'Already gone' -Message 'not found, deleted in the meantime'
                    } else {
                        AddNxoCleanupResult -State $state -Item $item -Status Failed -Message $_.Exception.Message
                    }
                    $finishedCount++
                }
                Start-Sleep -Milliseconds 500   # spread the deletions, Prism Central rate-limits its API
            }

            while ($running.Count) {
                Start-Sleep -Seconds 5
                foreach ($run in @($running)) {
                    $elapsed = ([datetime]::UtcNow - $run.Started).TotalSeconds
                    $rpPath = "/config/recovery-points/$($run.Item.RpExtId)"
                    $task = $null
                    try {
                        $task = (InvokeNxoApi -Connection $run.Item.Pc.Connection -Namespace prism -Path "/config/tasks/$($run.TaskId)").data
                        $run.PollErrors = 0
                    } catch {
                        # Task status not readable: log it, and after 3 tries check the recovery point itself.
                        $run.PollErrors++
                        $pollError = $_.Exception.Message
                        if ($run.PollErrors -eq 1) {
                            WriteNxoCleanupLog -State $state -Message ('Task status for {0} could not be read: {1}' -f $run.Item.RpExtId, $pollError) -Level WARN
                        }
                        if ($run.PollErrors -ge 3 -and (GetNxoLookupState -Connection $run.Item.Pc.Connection -Namespace dataprotection -Path $rpPath) -eq 'Missing') {
                            AddNxoCleanupResult -State $state -Item $run.Item -Status Deleted -Message "task status could not be read ($pollError), but the recovery point no longer exists"
                            [void]$running.Remove($run)
                            $finishedCount++
                            continue
                        }
                    }
                    if ($null -eq $task -or $task.status -in @('QUEUED', 'RUNNING', 'CANCELING')) {
                        if ($elapsed -ge $TimeoutSeconds) {
                            # Not reported as finished in time: check whether the recovery point is gone anyway.
                            switch (GetNxoLookupState -Connection $run.Item.Pc.Connection -Namespace dataprotection -Path $rpPath) {
                                'Missing' { $status = 'Deleted'; $message = "task $($run.TaskId) not reported as finished after $TimeoutSeconds s, but the recovery point no longer exists" }
                                'Exists' { $status = 'Timeout'; $message = "task $($run.TaskId) not finished after $TimeoutSeconds s and the recovery point still exists; check the task in Prism Central" }
                                default { $status = 'Timeout'; $message = "task $($run.TaskId) not finished after $TimeoutSeconds s and the recovery point could not be checked; check the task in Prism Central" }
                            }
                            AddNxoCleanupResult -State $state -Item $run.Item -Status $status -Message $message
                            [void]$running.Remove($run)
                            $finishedCount++
                        }
                        continue
                    }
                    if ($task.status -eq 'SUCCEEDED') {
                        AddNxoCleanupResult -State $state -Item $run.Item -Status Deleted
                    } else {
                        $detail = @($task.errorMessages | ForEach-Object { $_.message } | Where-Object { $_ }) -join '; '
                        if (-not $detail) { $detail = @($task.legacyErrorMessage) -join '; ' }
                        AddNxoCleanupResult -State $state -Item $run.Item -Status Failed -Message ('task {0}: {1}' -f $task.status, $detail)
                    }
                    [void]$running.Remove($run)
                    $finishedCount++
                }
                Write-Progress -Activity 'Deleting recovery points' -Status "$finishedCount of $($queue.Count) finished" -PercentComplete (100 * $finishedCount / $queue.Count)
            }
        }
        $completed = $true
    } finally {
        # Runs also after Ctrl+C or an unexpected error: whatever was deleted must end up in the results CSV and the storage history.
        Write-Progress -Activity 'Deleting recovery points' -Completed
        if (-not $completed) {
            foreach ($run in @($running)) {
                AddNxoCleanupResult -State $state -Item $run.Item -Status 'Not confirmed' -Message 'the deletion was started, but the run stopped before it finished; check it in Prism Central'
            }
            $notConfirmed = $running.Count
            $notStarted = $queue.Count - $state.Results.Count
            $stopText = 'Run stopped before the end: {0} of {1} finished, {2} not confirmed, {3} not started. The results so far are saved.' -f ($state.Results.Count - $notConfirmed), (FormatNxoCount -Count $queue.Count -Singular 'recovery point'), $notConfirmed, $notStarted
            Write-Host ''
            Write-Host $stopText -ForegroundColor Yellow
            WriteNxoCleanupLog -State $state -Message $stopText -Level WARN
        }
        $state.Results | Export-Csv -LiteralPath $resultsCsv -NoTypeInformation -UseCulture -Encoding utf8BOM -WhatIf:$false -Confirm:$false
        $deleted = @($state.Results | Where-Object Status -EQ 'Deleted')
        if (-not $dryRun -and $deleted.Count) {
            # Recorded so later runs can compare the storage with the state before this deletion.
            $historyRows = @($deleted | Group-Object -Property PrismCentral | ForEach-Object {
                    $freed = ($_.Group | Where-Object { $null -ne $_.SizeBytes } | Measure-Object -Property SizeBytes -Sum).Sum
                    ConvertToNxoStorageRow -State $state -EventName Deleted -PrismCentral $_.Name -DeletedCount $_.Count -FreedAtLeastBytes ([long]$freed)
                })
            AddNxoStorageHistory -State $state -Row $historyRows
        }
        if (-not $completed) {
            Write-Host "Log:     $($state.LogFile)"
            Write-Host "Results: $resultsCsv"
        }
    }

    $gone = @($state.Results | Where-Object Status -EQ 'Already gone')
    $skippedByUser = @($state.Results | Where-Object Status -EQ 'Skipped (not confirmed)')
    $problems = @($state.Results | Where-Object Status -In @('Failed', 'Timeout', 'Not confirmed'))
    Write-Host ''
    if ($dryRun) {
        Write-Host ' DRY RUN finished: nothing was deleted. ' -ForegroundColor Black -BackgroundColor Yellow
        Write-Host ('{0} would have been deleted, space {1}.' -f (FormatNxoCount -Count $queue.Count -Singular 'recovery point'), (FormatNxoTotal -Item $queue)) -ForegroundColor Cyan
    } else {
        Write-Host ' LIVE RUN finished ' -ForegroundColor White -BackgroundColor DarkRed
        Write-Host ('Deleted {0} of {1}, space to be freed: {2}.' -f $deleted.Count, (FormatNxoCount -Count $queue.Count -Singular 'recovery point'), (FormatNxoTotal -Item $deleted)) -ForegroundColor Cyan
        if ($gone.Count) { Write-Host ('{0} already gone (for example deleted together with a copy).' -f (FormatNxoCount -Count $gone.Count -Singular 'was' -Plural 'were')) }
        if ($skippedByUser.Count) { Write-Host ('{0} skipped because you answered No in the confirmation prompt.' -f (FormatNxoCount -Count $skippedByUser.Count -Singular 'recovery point')) -ForegroundColor Yellow }
        if ($problems.Count) {
            Write-Host "$($problems.Count) not deleted or not confirmed:" -ForegroundColor Red
            $problems | Format-Table -AutoSize -Wrap -Property Status, Name, RecoveryPointName, PrismCentral, Message | Out-String -Width ([Math]::Max(120, $Host.UI.RawUI.BufferSize.Width)) | Write-Host
            if ($problems.Status -contains 'Failed') {
                Write-Host 'Failed: these still exist and are listed again in the next run, so you can simply run the cleanup again.'
            }
            if ($problems.Status -contains 'Timeout') {
                Write-Host 'Timeout: the deletion was started but not confirmed in time. Check the tasks in Prism Central;'
                Write-Host 'whatever still exists is listed again in the next run.'
            }
            if ($problems.Message -match 'rate limit') {
                Write-Host 'Some failed because of the API rate limit: run it again with -BatchSize 2.' -ForegroundColor Yellow
            }
            Write-Host 'If expired recovery points keep failing for other reasons, open a case with Nutanix support.'
        }
        if ($deleted.Count) {
            Write-Host 'To see how much space was actually freed, run this tomorrow with the same log folder:' -ForegroundColor Cyan
            Write-Host '  Invoke-NxoRecoveryPointCleanup -StorageReport' -ForegroundColor Cyan
        }
    }
    WriteNxoCleanupLog -State $state -Message ('Finished ({0}): deleted={1}, already gone={2}, skipped by user={3}, not deleted or not confirmed={4}' -f $mode, $deleted.Count, $gone.Count, $skippedByUser.Count, $problems.Count)
    Write-Host "Log:     $($state.LogFile)"
    Write-Host "Results: $resultsCsv"
    #endregion
}
