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

Describe 'Test-NxoUpgradeReadiness with a simulated Prism Central' {
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
    Describe 'Test-NxoUpgradeReadiness' {
        BeforeEach {
            Mock Write-Host {}
            $reportFolder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid())
        }

        It 'Runs all checks non-interactively and writes the report' {
            $result = @(Test-NxoUpgradeReadiness -ClusterName 'NTNX-CL01' -ChangeId 'CHG1' -NonInteractive -ReportFolder $reportFolder -NccReportRecipient 'ops@example.com')
            $checks = @{}
            foreach ($row in $result) { $checks[$row.Check] = $row }

            $checks['Cluster and host state'].Result | Should -Be 'PASS'
            $checks['Data resiliency'].Result | Should -Be 'PASS'
            $checks['Storage (resilient capacity)'].Value | Should -Be '26.7 %'
            $checks['HA reservation'].Value | Should -Be 'Not confirmed'
            $checks['Memory with N-1'].Result | Should -Be 'PASS'
            $checks['CPU peak with N-1'].Value | Should -Be '60 %'
            $checks['CPU Ready'].Result | Should -Be 'WARN'
            $checks['GPU with N-1'].Result | Should -Be 'PASS'
            $checks['Non-migratable VMs'].Value | Should -Be '1 VM(s)'
            $checks['NCC health checks'].Value | Should -Be '9/10 PASS'
            $checks['Alert: Disk sda high'].Justification | Should -Be '(no justification provided)'

            $result[0].Verdict | Should -Be 'GO WITH RESERVATIONS'
            $result[0].PSObject.TypeNames[0] | Should -Be 'PSNutanixOps.UpgradeReadinessCheck'
            Test-Path -LiteralPath $result[0].ReportPath | Should -BeTrue
            Split-Path -Path $result[0].ReportPath -Leaf | Should -BeLike 'UpgradeReadiness_NTNX-CL01_CHG1_*.html'
        }

        It 'Records the interactive answers' {
            $script:answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('Y', 'ready is known', 'pinned VM', 'ncc ok', 'disk ok'))
            Mock Read-Host { $script:answers.Dequeue() }
            $result = @(Test-NxoUpgradeReadiness -ReportFolder $reportFolder -SkipNcc)
            ($result | Where-Object Check -EQ 'HA reservation').Result | Should -Be 'PASS'
            ($result | Where-Object Check -EQ 'CPU Ready').Justification | Should -Be 'ready is known'
            ($result | Where-Object Check -EQ 'NCC health checks').Result | Should -Be 'SKIPPED'
        }

        It 'Reports NO-GO on resource shortage' {
            $result = @(Test-NxoUpgradeReadiness -NonInteractive -SkipNcc -SkipCpuReady -CpuThresholdPercent 50 -ReportFolder $reportFolder)
            ($result | Where-Object Check -EQ 'CPU peak with N-1').Result | Should -Be 'FAIL'
            ($result | Where-Object Check -EQ 'CPU Ready').Result | Should -Be 'SKIPPED'
            $result[0].Verdict | Should -Be 'NO-GO'
        }

        It 'Warns when no cluster matches' {
            Mock Write-Warning {}
            Test-NxoUpgradeReadiness -ClusterName 'OTHER' -NonInteractive -ReportFolder $reportFolder | Should -BeNullOrEmpty
            Should -Invoke Write-Warning -ParameterFilter { $Message -like 'No matching clusters*' }
        }

        It 'Keeps going when data sources fail' {
            Mock Write-Warning {}
            Mock GetNxoStatSeries { throw 'stats down' }
            Mock GetNxoPagedList { throw 'alerts down' } -ParameterFilter { $Path -eq '/serviceability/alerts' }
            Mock GetNxoPagedList { throw 'stats down' } -ParameterFilter { $Path -eq '/ahv/stats/vms' }
            $result = @(Test-NxoUpgradeReadiness -NonInteractive -SkipNcc -ReportFolder $reportFolder)
            ($result | Where-Object Check -EQ 'Storage (resilient capacity)').Value | Should -Be 'n/a'
            ($result | Where-Object Check -EQ 'CPU peak with N-1').Value | Should -Be 'n/a'
            ($result | Where-Object Check -EQ 'CPU Ready').Result | Should -Be 'SKIPPED'
            ($result | Where-Object Check -EQ 'Open alerts').Result | Should -Be 'WARN'
        }
    }
}
