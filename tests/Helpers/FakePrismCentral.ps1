<#
.SYNOPSIS
    Simulated Prism Central v4 API for the unit tests of the public commands.
.DESCRIPTION
    Dot-source this file in BeforeAll, call Reset-FakeNxoData in BeforeEach and mock the
    single HTTP entry point of the module:

        Mock InvokeNxoRestMethod { Invoke-FakeNxoRestMethod -Method $Method -Path $Path -Body $Body }

    The data set holds one AOS cluster (NTNX-CL01, four hosts) plus the Prism Central
    self-registration, three VMs, categories, a subnet, three recovery points, alerts, events
    and NCC results. clustermgmt answers 404 for revision v4.3, so the revision negotiation
    falls back to v4.2. Every request is recorded in $script:FakeNxoCalls.
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Test helper')]
param()

function New-FakeNxoHttpError {
    param([int]$StatusCode, [string]$Message = 'Response status code does not indicate success')
    $exception = [System.Exception]::new("$Message ($StatusCode)")
    $exception.Data['StatusCode'] = $StatusCode
    throw $exception
}

function Reset-FakeNxoData {
    $now = [datetime]::UtcNow
    $script:FakeNxoCalls = [System.Collections.Generic.List[string]]::new()
    $script:FakeNxoData = @{
        Now        = $now
        Vms        = @(
            [PSCustomObject]@{
                extId = 'vm-1'; name = 'APP01'; description = 'MFA'; powerState = 'ON'; createTime = $now.AddYears(-5); updateTime = $now.AddDays(-10)
                numSockets = 2; numCoresPerSocket = 1; numThreadsPerCore = 1; memorySizeBytes = 4GB; isLiveMigrateCapable = $true
                bootConfig = [PSCustomObject]@{ '$objectType' = 'vmm.v4.ahv.config.LegacyBoot' }; vtpmConfig = [PSCustomObject]@{ isVtpmEnabled = $false }
                machineType = 'PC'; protectionType = 'UNPROTECTED'; cluster = [PSCustomObject]@{ extId = 'cl-1' }; host = [PSCustomObject]@{ extId = 'h-1' }
                categories = @([PSCustomObject]@{ extId = 'cat-1' }, [PSCustomObject]@{ extId = 'cat-2' })
                guestTools = [PSCustomObject]@{ version = '4.3.1'; isInstalled = $true; availableVersion = '4.5.1.8'; guestOsVersion = 'windows:64:WindowsServer2019Standard'; isReachable = $true; isEnabled = $true }
                disks = @([PSCustomObject]@{ backingInfo = [PSCustomObject]@{ diskSizeBytes = 100GB } }, [PSCustomObject]@{ backingInfo = [PSCustomObject]@{ diskSizeBytes = 50GB } })
                nics = @([PSCustomObject]@{
                        nicBackingInfo = [PSCustomObject]@{ macAddress = '50:6b:8d:aa:bb:cc' }
                        nicNetworkInfo = [PSCustomObject]@{ subnet = [PSCustomObject]@{ extId = 'sn-1' }; ipv4Config = [PSCustomObject]@{ ipAddress = [PSCustomObject]@{ value = '10.0.0.5' } } }
                    })
            }
            [PSCustomObject]@{
                extId = 'vm-2'; name = 'SQL01'; powerState = 'ON'; numSockets = 4; numCoresPerSocket = 2; memorySizeBytes = 32GB; isLiveMigrateCapable = $false
                cluster = [PSCustomObject]@{ extId = 'cl-1' }; host = [PSCustomObject]@{ extId = 'h-2' }; categories = @([PSCustomObject]@{ extId = 'cat-3' })
            }
            [PSCustomObject]@{ extId = 'vm-3'; name = 'OFF01'; powerState = 'OFF'; numSockets = 1; numCoresPerSocket = 1; memorySizeBytes = 2GB; cluster = [PSCustomObject]@{ extId = 'cl-1' } }
        )
        Categories = @(
            [PSCustomObject]@{ extId = 'cat-1'; key = 'Env'; value = 'Prod' }
            [PSCustomObject]@{ extId = 'cat-2'; key = 'App'; value = 'Citrix' }
            [PSCustomObject]@{ extId = 'cat-3'; key = 'Workload'; value = 'SQL' }
        )
        Rps        = [System.Collections.Generic.List[object]]::new()
        Tasks      = @{}
        NccDetails = @(
            [PSCustomObject]@{ name = 'total'; value = '10' }
            [PSCustomObject]@{ name = 'pass'; value = '9' }
            [PSCustomObject]@{ name = 'warn'; value = '1' }
            [PSCustomObject]@{ name = 'detailedSummary'; value = @([PSCustomObject]@{ map = [PSCustomObject]@{ warnSdaExtIds = '101061' } }) }
        )
    }
    $rps = $script:FakeNxoData.Rps
    $rps.Add([PSCustomObject]@{ extId = 'rp-1'; name = 'OnDemand-1'; status = 'COMPLETE'; recoveryPointType = 'CRASH_CONSISTENT'; creationTime = $now.AddDays(-40); expirationTime = $now.AddDays(-35); vmRecoveryPoints = @([PSCustomObject]@{ extId = 'vmrp-1'; vmExtId = 'vm-1'; hypervisorType = 'AHV' }); totalExclusiveUsageBytes = 5GB })
    $rps.Add([PSCustomObject]@{ extId = 'rp-2'; name = 'Daily'; status = 'COMPLETE'; recoveryPointType = 'CRASH_CONSISTENT'; creationTime = $now.AddDays(-60); expirationTime = $now.AddDays(30); vmRecoveryPoints = @([PSCustomObject]@{ extId = 'vmrp-2'; vmExtId = 'vm-gone'; hypervisorType = 'AHV' }) })
    $rps.Add([PSCustomObject]@{ extId = 'rp-3'; name = 'Fresh'; status = 'COMPLETE'; recoveryPointType = 'CRASH_CONSISTENT'; creationTime = $now.AddDays(-1); expirationTime = $now.AddDays(5); vmRecoveryPoints = @([PSCustomObject]@{ vmExtId = 'vm-2' }) })
}

function Invoke-FakeNxoRestMethod {
    param([string]$Method = 'GET', [string]$Path, $Body)

    $script:FakeNxoCalls.Add("$Method $Path")
    $data = $script:FakeNxoData
    $now = $data.Now
    $parts = $Path -split '\?', 2
    $route = $parts[0]
    $query = if ($parts.Count -gt 1) { [uri]::UnescapeDataString($parts[1]) } else { '' }
    $page = if ($query -match '\$page=(\d+)') { [int]$Matches[1] } else { 0 }

    $list = {
        param($Items)
        if ($page -gt 0) { return [PSCustomObject]@{ data = @() } }
        [PSCustomObject]@{ data = @($Items); metadata = [PSCustomObject]@{ totalAvailableResults = @($Items).Count } }
    }
    $task = {
        param([string]$Id, [hashtable]$Extra = @{})
        $taskData = [ordered]@{ extId = $Id; status = 'SUCCEEDED'; progressPercentage = 100; completedTime = $now }
        foreach ($key in $Extra.Keys) { $taskData[$key] = $Extra[$key] }
        $data.Tasks[$Id] = [PSCustomObject]$taskData
        [PSCustomObject]@{ data = [PSCustomObject]@{ extId = $Id } }
    }
    $stats = {
        # Three samples per field: the newest (1 h ago) has the base value, older ones 2x and 3x.
        param([hashtable]$FieldBase)
        $series = [ordered]@{}
        foreach ($field in $FieldBase.Keys) {
            $base = [double]$FieldBase[$field]
            $series[$field] = @(1..3 | ForEach-Object { [PSCustomObject]@{ timestamp = $now.AddHours(-$_); value = $base * $_ } })
        }
        [PSCustomObject]@{ data = [PSCustomObject]$series }
    }

    if ($route -match '^/clustermgmt/v4\.3/') { New-FakeNxoHttpError -StatusCode 404 }

    switch -Regex ($route) {
        '^/vmm/v4\.\d/ahv/config/vms$' { return & $list $data.Vms }
        '^/vmm/v4\.\d/ahv/config/vms/(.+)$' {
            $vm = $data.Vms | Where-Object { $_.extId -eq $Matches[1] }
            if ($vm) { return [PSCustomObject]@{ data = $vm } }
            New-FakeNxoHttpError -StatusCode 404
        }
        '^/vmm/v4\.\d/esxi/' { New-FakeNxoHttpError -StatusCode 404 }
        '^/vmm/v4\.\d/ahv/config/vm-recovery-points/' { return [PSCustomObject]@{ data = [PSCustomObject]@{ vm = [PSCustomObject]@{ name = 'OLD-VM' } } } }
        '^/vmm/v4\.\d/ahv/stats/vms/(.+)$' {
            return [PSCustomObject]@{ data = [PSCustomObject]@{ stats = @(1..4 | ForEach-Object { [PSCustomObject]@{ timestamp = $now.AddMinutes(-5 * $_); hypervisorCpuReadyTimePpm = 20000 * $_; hypervisorCpuUsagePpm = 300000 } }) } }
        }
        '^/vmm/v4\.\d/ahv/stats/vms$' {
            return & $list @($data.Vms | Select-Object -First 2 | ForEach-Object { [PSCustomObject]@{ extId = $_.extId; stats = @([PSCustomObject]@{ timestamp = $now; hypervisorCpuReadyTimePpm = 70000 }) } })
        }
        '^/clustermgmt/v4\.\d/config/clusters$' {
            return & $list @(
                [PSCustomObject]@{ extId = 'cl-1'; name = 'NTNX-CL01'; config = [PSCustomObject]@{ clusterFunction = @('AOS'); redundancyFactor = 2; buildInfo = [PSCustomObject]@{ version = '7.3' }; faultToleranceState = [PSCustomObject]@{ currentMaxFaultTolerance = 1; desiredMaxFaultTolerance = 1; domainAwarenessLevel = 'NODE' } } }
                [PSCustomObject]@{ extId = 'pc-self'; name = 'PC'; config = [PSCustomObject]@{ clusterFunction = @('PRISM_CENTRAL') } }
            )
        }
        '^/clustermgmt/v4\.\d/config/hosts$' { return & $list @(1..4 | ForEach-Object { [PSCustomObject]@{ extId = "h-$_"; hostName = "ntnx-h$_" } }) }
        '^/clustermgmt/v4\.\d/config/clusters/cl-1/hosts$' {
            return & $list @(1..4 | ForEach-Object { [PSCustomObject]@{ extId = "h-$_"; hostName = "ntnx-h$_"; hostType = 'HYPER_CONVERGED'; nodeStatus = 'NORMAL'; maintenanceState = 'normal'; numberOfCpuCores = 32; memorySizeBytes = 512GB } })
        }
        '^/clustermgmt/v4\.\d/config/clusters/cl-1/cvms$' { return & $list @(1..4 | ForEach-Object { [PSCustomObject]@{ nodeExtId = "h-$_"; name = "NTNX-$_-CVM"; memorySizeBytes = 32GB } }) }
        '^/clustermgmt/v4\.\d/stats/clusters/cl-1$' {
            if ($query -match 'statType=LAST') { return & $stats @{ storageCapacityBytes = 100TB; storageUsageBytes = 20TB; logicalStorageUsageBytes = 40TB } }
            return & $stats @{ hypervisorCpuUsagePpm = 150000 }
        }
        '^/clustermgmt/v4\.\d/stats/clusters/cl-1/hosts/' {
            if ($query -match 'statType=LAST') { return & $stats @{ memoryCapacityBytes = 512GB; storageCapacityBytes = 25TB } }
            return & $stats @{ hypervisorCpuUsagePpm = 200000 }
        }
        'compute-non-migratable-vms$' { return & $task 'task-nm' @{ entitiesAffected = @([PSCustomObject]@{ extId = '11111111-2222-3333-4444-555555555555' }) } }
        'non-migratable-vms-result' { return [PSCustomObject]@{ data = [PSCustomObject]@{ vms = @() } } }
        'gpu-profiles$' { return & $list @() }
        '^/prism/v4\.\d/config/categories$' {
            if ($query -match "key eq '([^']+)' and value eq '([^']+)'") {
                $key = $Matches[1]
                $value = $Matches[2]
                return [PSCustomObject]@{ data = @($data.Categories | Where-Object { $_.key -eq $key -and $_.value -eq $value }) }
            }
            return & $list $data.Categories
        }
        '^/prism/v4\.\d/config/tasks/(.+)$' {
            $id = $Matches[1]
            if ($data.Tasks.ContainsKey($id)) { return [PSCustomObject]@{ data = $data.Tasks[$id] } }
            New-FakeNxoHttpError -StatusCode 404
        }
        '^/networking/v4\.\d/config/subnets$' { return & $list @([PSCustomObject]@{ extId = 'sn-1'; name = 'VLAN100-Servers' }) }
        '^/dataprotection/v4\.\d/config/recovery-points$' {
            if ($Method -eq 'POST') { return & $task ('task-create-{0}' -f $script:FakeNxoCalls.Count) }
            return & $list $data.Rps
        }
        '^/dataprotection/v4\.\d/config/recovery-points/(.+)$' {
            $id = $Matches[1]
            $recoveryPoint = $data.Rps | Where-Object { $_.extId -eq $id }
            if (-not $recoveryPoint) { New-FakeNxoHttpError -StatusCode 404 }
            if ($Method -eq 'DELETE') {
                [void]$data.Rps.Remove($recoveryPoint)
                return & $task "task-del-$id"
            }
            return [PSCustomObject]@{ data = $recoveryPoint }
        }
        '^/volumes/v4\.\d/config/volume-groups$' { return & $list @() }
        'run-system-defined-checks$' { return & $task 'ncc-task' @{ completionDetails = $data.NccDetails } }
        '^/monitoring/v4\.\d/serviceability/alerts$' {
            return & $list @(
                [PSCustomObject]@{ severity = 'WARNING'; title = 'Disk {disk} high'; message = 'Disk {disk} usage high'; parameters = @([PSCustomObject]@{ paramName = 'disk'; paramValue = [PSCustomObject]@{ stringValue = 'sda' } }); creationTime = $now.AddDays(-1); clusterUUID = 'cl-1'; isResolved = $false; isAcknowledged = $false }
                [PSCustomObject]@{ severity = 'CRITICAL'; title = 'Old'; message = 'old'; creationTime = $now.AddDays(-3); clusterUUID = 'cl-1'; isResolved = $false; isAcknowledged = $true; acknowledgedByUsername = 'admin' }
            )
        }
        '^/monitoring/v4\.\d/serviceability/events$' { return & $list @([PSCustomObject]@{ creationTime = $now; eventType = 'NccRun'; serviceName = 'ncc'; message = 'NCC finished'; clusterUUID = 'cl-1' }) }
        'system-defined-policies/' { return [PSCustomObject]@{ data = [PSCustomObject]@{ title = 'Check Disk Space'; kbArticles = @('https://portal.nutanix.com/kb/1234') } } }
        default { throw "Fake Prism Central: no route for $Method $Path" }
    }
}
