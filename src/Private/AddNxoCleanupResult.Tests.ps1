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

Describe 'AddNxoCleanupResult' {
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

    It 'Records <Status> with log level <Level>' -TestCases @(
        @{ Status = 'Deleted'; Level = 'INFO'; Color = 'Green' }
        @{ Status = 'Skipped (not confirmed)'; Level = 'INFO'; Color = 'Yellow' }
        @{ Status = 'Failed'; Level = 'ERROR'; Color = 'Red' }
    ) {
        AddNxoCleanupResult -State $testState -Item $testItem -Status $Status -Message 'detail'
        $testState.Results.Count | Should -Be 1
        $testState.Results[0].Status | Should -Be $Status
        $testState.Results[0].RecoveryPointExtId | Should -Be 'rp-1'
        Should -Invoke Write-Host -ParameterFilter { $ForegroundColor -eq $Color -and $Object -like "*: SQL01 / Daily on PC1 - detail" }
        Get-Content -LiteralPath $testState.LogFile | Should -Match "\[$Level\] .*\[rp-1\] on pc01$"
    }

    It 'Rejects unknown states' {
        { AddNxoCleanupResult -State $testState -Item $testItem -Status 'Gone' } | Should -Throw
    }
}
