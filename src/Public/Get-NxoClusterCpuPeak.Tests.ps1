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

Describe 'Get-NxoClusterCpuPeak with a simulated Prism Central' {
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
    Describe 'Get-NxoClusterCpuPeak' {
        It 'Returns the cluster row first, then the hosts' {
            $result = @(Get-NxoClusterCpuPeak)
            $result.Count | Should -Be 5
            $result[0].Scope | Should -Be 'Cluster'
            $result[0].Nodes | Should -Be 4
            $result[0].MaxCpuPct | Should -Be 45
            $result[0].ProjectedN1Pct | Should -Be 60
            $result[0].Status | Should -Be 'OK'
            @($result | Where-Object Scope -EQ 'Host').Name | Sort-Object | Should -Be @('ntnx-h1', 'ntnx-h2', 'ntnx-h3', 'ntnx-h4')
        }

        It 'Falls back from v4.3 to v4.2 for clustermgmt' {
            $connection = (GetNxoConnectionStore)['pc01.example.local']
            $connection.ApiVersion = 'v4.3'
            $null = Get-NxoClusterCpuPeak -ClusterOnly
            $connection.NamespaceVersion['clustermgmt@v4.3'] | Should -Be 'v4.2'
        }

        It 'Returns only cluster rows with -ClusterOnly and warns above the threshold' {
            $result = @(Get-NxoClusterCpuPeak -ClusterOnly -ThresholdPercent 50)
            $result.Count | Should -Be 1
            $result[0].Status | Should -Be 'WARN'
        }

        It 'Returns samples with -Raw' {
            $raw = @(Get-NxoClusterCpuPeak -ClusterOnly -Raw)
            $raw.Count | Should -Be 3
            $raw[0].PSObject.TypeNames[0] | Should -Be 'PSNutanixOps.ClusterCpuSample'
        }

        It 'Warns when no cluster matches' {
            Mock Write-Warning {}
            Get-NxoClusterCpuPeak -ClusterName 'OTHER' | Should -BeNullOrEmpty
            Should -Invoke Write-Warning -ParameterFilter { $Message -like 'No matching clusters*' }
        }

        It 'Reports NO DATA when stats fail' {
            Mock GetNxoStatSeries { throw 'stats failed' }
            Mock Write-Warning {}
            @(Get-NxoClusterCpuPeak -ClusterOnly)[0].Status | Should -Be 'NO DATA'
        }

        It 'Skips a cluster whose host list fails and a Prism Central whose cluster list fails' {
            Mock Write-Warning {}
            Mock GetNxoPagedList { throw 'hosts failed' } -ParameterFilter { $Path -like '*/hosts' }
            Get-NxoClusterCpuPeak | Should -BeNullOrEmpty
            Mock GetNxoClusterList { throw 'clusters failed' }
            Get-NxoClusterCpuPeak | Should -BeNullOrEmpty
            Should -Invoke Write-Warning -ParameterFilter { $Message -like 'Skipping Prism Central*' }
        }

        It 'Validates the time window' {
            { Get-NxoClusterCpuPeak -StartTime (Get-Date) -EndTime (Get-Date).AddHours(-1) } | Should -Throw
        }
    }
}
