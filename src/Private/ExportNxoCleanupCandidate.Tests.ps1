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

Describe 'ExportNxoCleanupCandidate' {
    BeforeEach {
        $testState = @{
            Mode = 'LIVE'; DryRun = $false; TotalSteps = 5; Stamp = '20261028-120000'
            LogFile = Join-Path -Path $TestDrive -ChildPath ('cleanup-{0}.log' -f [guid]::NewGuid())
            StorageFile = Join-Path -Path $TestDrive -ChildPath ('storage-history-{0}.csv' -f [guid]::NewGuid())
            Results = [System.Collections.Generic.List[object]]::new()
        }

        $testPc = [PSCustomObject]@{ Label = 'PC1'; Address = 'pc01' }
        $testItem = [PSCustomObject]@{
            Reason = 'Expired'; Type = 'VM'; Name = 'SQL01'; VmIds = @('vm-1'); VgIds = @(); Pc = $testPc; RpExtId = 'rp-1'; RpName = 'Daily'
            LocationAgnosticId = 'loc-1'; CreatedUtc = [datetime]::UtcNow.AddDays(-40); ExpiresUtc = [datetime]::UtcNow.AddDays(-5); SizeBytes = 1GB
        }
        $testRow = [PSCustomObject]@{
            Row = 1; Reason = 'Expired'; Name = ('A' * 50); Pcs = 'PC1'; Count = 1; OldestUtc = $testItem.CreatedUtc; NewestUtc = $testItem.CreatedUtc
            EntityNewestUtc = [datetime]::UtcNow; OverdueDays = 5; SizeBytes = 1GB; UnknownSize = 0; Items = @($testItem)
        }
        Mock Write-Host {}
    }

    It 'Writes one line per recovery point' {
        $path = Join-Path -Path $TestDrive -ChildPath 'list.csv'
        ExportNxoCleanupCandidate -State $testState -Row @($testRow) -Path $path
        $lines = @(Import-Csv -LiteralPath $path -UseCulture)
        $lines.Count | Should -Be 1
        $lines[0].RecoveryPointExtId | Should -Be 'rp-1'
        $lines[0].PrismCentral | Should -Be 'pc01'
        $lines[0].Size | Should -Be '1.0 GiB'
        $lines[0].VmExtIds | Should -Be 'vm-1'
        Get-Content -LiteralPath $testState.LogFile | Should -BeLike "*Exported list to $path"
    }
}
