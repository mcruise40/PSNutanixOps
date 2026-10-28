[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables used in Pester test contexts')]
param()

BeforeAll {
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

Describe 'ExportNxoUpgradeReport' {
    BeforeEach {
        $folder = Join-Path -Path $TestDrive -ChildPath 'reports'
        $null = New-Item -ItemType Directory -Path $folder -Force
        $cluster = [PSCustomObject]@{ extId = 'c1'; name = 'NTNX/CL01' }
        $checks = @(
            [PSCustomObject]@{ Check = 'CPU <peak>'; Result = 'PASS'; Value = '60 %'; Threshold = '<= 80 %'; Detail = 'ok'; Justification = $null }
            [PSCustomObject]@{ Check = 'Alert'; Result = 'WARN'; Value = 'WARNING'; Threshold = 'none'; Detail = 'disk'; Justification = 'known & accepted' }
        )
        $extra = @{
            Info          = [ordered]@{ 'AOS version' = '7.3' }
            Hosts         = @([PSCustomObject]@{ Host = 'ntnx-h1'; Type = 'HYPER_CONVERGED'; NodeStatus = 'NORMAL'; Maintenance = 'normal'; MemoryBytes = 512GB; StorageBytes = 10TB; MaxCpuPct = 60; MaxCpuAt = Get-Date; GpuNames = '' })
            NonMigratable = @([PSCustomObject]@{ VM = 'SQL01'; Reason = 'pinned'; Host = 'ntnx-h1' })
            CpuReady      = @([PSCustomObject]@{ VM = 'SQL01'; MaxReadyPct = 7; At = Get-Date })
            AckAlerts     = @([PSCustomObject]@{ Severity = 'CRITICAL'; Title = 'Old'; Created = Get-Date; AcknowledgedBy = 'admin' })
            Ncc           = [ordered]@{
                Status = 'SUCCEEDED'; Started = (Get-Date).AddMinutes(-10); Completed = Get-Date; Duration = '10 min'; Recipients = 'ops'
                TaskId = 'ncc-1'; Details = @('Step: x'); Overall = 'WARN'; Counts = [ordered]@{ total = 10; pass = 9; warn = 1; fail = 0 }
                Checks = @([PSCustomObject]@{ Category = 'WARN'; CheckId = '101'; Title = $null; Kb = 'https://portal.nutanix.com/kb/1, KB2' })
                Events = @([PSCustomObject]@{ Time = Get-Date; Type = 'E'; Message = 'm' })
                NewAlerts = @([PSCustomObject]@{ Severity = 'WARNING'; Title = 'New'; Created = Get-Date })
            }
        }
        $param = @{
            Folder = $folder; PrismCentral = 'pc01'; Cluster = $cluster; Verdict = 'GO WITH RESERVATIONS'; Check = $checks
            Extra = $extra; Engineer = 'tester'; StartTime = [datetime]'2026-10-21T10:00:00'; EndTime = [datetime]'2026-10-28T10:00:00'
        }
    }

    It 'Writes the report with a safe file name' {
        $path = ExportNxoUpgradeReport @param -ChangeId 'CHG 0012345'
        Split-Path -Path $path -Leaf | Should -Be 'UpgradeReadiness_NTNX_CL01_CHG_0012345_20261028-1000.html'
        Test-Path -LiteralPath $path | Should -BeTrue
    }

    It 'Encodes values and contains all sections' {
        $html = Get-Content -LiteralPath (ExportNxoUpgradeReport @param) -Raw
        $html | Should -Match 'CPU &lt;peak&gt;'
        $html | Should -Match 'Justification: known &amp; accepted'
        $html | Should -Match '<h2>NCC run</h2>'
        $html | Should -Match '<h2>Non-migratable VMs</h2>'
        $html | Should -Match '<h2>Highest CPU Ready \(top 10\)</h2>'
        $html | Should -Match '<h2>Acknowledged alerts \(information\)</h2>'
        $html | Should -Match "<a href='https://portal.nutanix.com/kb/1'>portal.nutanix.com/kb/1</a>, KB2"
        $html | Should -Match '\(name not available via API\)'
        $html | Should -Match '512 GiB'
    }

    It 'Leaves out empty sections' {
        $param.Extra = @{ Info = [ordered]@{}; Hosts = @(); NonMigratable = @(); CpuReady = @(); AckAlerts = @(); Ncc = $null }
        $param.Verdict = 'GO'
        $html = Get-Content -LiteralPath (ExportNxoUpgradeReport @param) -Raw
        $html | Should -Not -Match 'NCC run'
        $html | Should -Not -Match 'Non-migratable'
        $html | Should -Match 'verdict pass'
    }
}
