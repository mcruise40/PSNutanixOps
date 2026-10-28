[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables used in Pester test contexts')]
param()

BeforeAll {
    # The CI runs the tests under Set-StrictMode -Version Latest. Nutanix API objects have many optional
    # properties that the module reads without strict mode, the same way it runs for users: a module does
    # not inherit the strict mode of its caller. The functions under test are dot-sourced into the test
    # scope, so strict mode is switched off here (inherited by all blocks and tests of this file).
    Set-StrictMode -Off
    $sourceRoot = Split-Path -Path $PSScriptRoot -Parent
    $sourceFiles = Get-ChildItem -Path (Join-Path -Path $sourceRoot -ChildPath 'Private'), (Join-Path -Path $sourceRoot -ChildPath 'Public') -Filter '*.ps1' |
        Where-Object { $_.Name -notlike '*.Tests.ps1' }
    foreach ($sourceFile in $sourceFiles) { . $sourceFile.FullName }

    $testCredential = [System.Management.Automation.PSCredential]::new('admin', (ConvertTo-SecureString -String 'secret' -AsPlainText -Force))
    function New-TestConnection {
        [PSCustomObject]@{
            Server               = 'pc01.example.local'
            Port                 = 9440
            Credential           = $testCredential
            ApiVersion           = 'v4.2'
            SkipCertificateCheck = $true
            ConnectedAt          = Get-Date
            NamespaceVersion     = @{}
        }
    }
    function New-TestHttpError {
        param([int]$StatusCode, [string]$Message = 'failed')
        $exception = [System.Exception]::new($Message)
        $exception.Data['StatusCode'] = $StatusCode
        $exception
    }
}

Describe 'Get-NxoVmCpuReady with a simulated Prism Central' {
    BeforeEach {
        . (Join-Path -Path $PSScriptRoot -ChildPath '../../tests/Helpers/FakePrismCentral.ps1')
        Reset-FakeNxoData
        $store = GetNxoConnectionStore
        $store.Clear()
        $store['pc01.example.local'] = New-TestConnection
        Mock InvokeNxoRestMethod { Invoke-FakeNxoRestMethod -Method $Method -Path $Path -Body $Body }
        Mock Start-Sleep {}
        Mock Write-Progress {}
    }

    AfterAll {
        (GetNxoConnectionStore).Clear()
    }
    Describe 'Get-NxoVmCpuReady' {
        It 'Summarizes the powered-on VMs' {
            $result = @(Get-NxoVmCpuReady)
            $result.Count | Should -Be 2
            $sql = $result | Where-Object VM -EQ 'SQL01'
            $sql.vCPUs | Should -Be 8
            $sql.Samples | Should -Be 4
            $sql.AvgReadyPct | Should -Be 5
            $sql.MaxReadyPct | Should -Be 8
            $sql.AboveThreshold | Should -Be 2
            $sql.Status | Should -Be 'WARN'
            $sql.AvgCpuUsagePct | Should -Be 30
            $sql.Cluster | Should -Be 'NTNX-CL01'
            $sql.PSObject.TypeNames[0] | Should -Be 'PSNutanixOps.VmCpuReady'
        }

        It 'Uses the threshold' {
            @(Get-NxoVmCpuReady -ThresholdPercent 10).Status | Should -Be @('OK', 'OK')
        }

        It 'Selects VMs by category' {
            @(Get-NxoVmCpuReady -CategoryKey 'Workload' -CategoryValue 'SQL').VM | Should -Be @('SQL01')
        }

        It 'Warns about an unknown category' {
            Mock Write-Warning {}
            Get-NxoVmCpuReady -CategoryKey 'Workload' -CategoryValue 'None' | Should -BeNullOrEmpty
            Should -Invoke Write-Warning -ParameterFilter { $Message -like "No category 'Workload:None'*" }
        }

        It 'Returns samples with -Raw and includes powered-off VMs on request' {
            $raw = @(Get-NxoVmCpuReady -VmName 'OFF01' -IncludePoweredOff -Raw)
            $raw.Count | Should -Be 4
            $raw[0].PSObject.TypeNames[0] | Should -Be 'PSNutanixOps.VmCpuReadySample'
            $raw[0].CpuUsagePct | Should -Be 30
        }

        It 'Reports NO DATA for VMs without samples' {
            Mock GetNxoVmStatSample {}
            (Get-NxoVmCpuReady -VmName 'APP01').Status | Should -Be 'NO DATA'
        }

        It 'Filters by cluster' {
            @(Get-NxoVmCpuReady -ClusterName 'NTNX-CL01').Count | Should -Be 2
            Mock Write-Warning {}
            Get-NxoVmCpuReady -ClusterName 'OTHER' | Should -BeNullOrEmpty
        }

        It 'Continues after a failing VM' {
            Mock InvokeNxoRestMethod {
                if ($Path -like '*/ahv/stats/vms/vm-1?*') { throw 'stats failed' }
                Invoke-FakeNxoRestMethod -Method $Method -Path $Path -Body $Body
            }
            Mock Write-Warning {}
            @(Get-NxoVmCpuReady).VM | Should -Be @('SQL01')
            Should -Invoke Write-Warning -Times 1 -Exactly
        }

        It 'Validates the time window' {
            { Get-NxoVmCpuReady -StartTime (Get-Date) -EndTime (Get-Date).AddHours(-1) } | Should -Throw '*-StartTime must be before -EndTime*'
        }
    }
}
