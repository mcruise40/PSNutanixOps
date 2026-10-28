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

Describe 'ShowNxoStorageComparison' {
    BeforeEach {
        $testState = @{
            Mode = 'LIVE'; DryRun = $false; TotalSteps = 5; Stamp = '20261028-120000'
            LogFile = Join-Path -Path $TestDrive -ChildPath ('cleanup-{0}.log' -f [guid]::NewGuid())
            StorageFile = Join-Path -Path $TestDrive -ChildPath ('storage-history-{0}.csv' -f [guid]::NewGuid())
            Results = [System.Collections.Generic.List[object]]::new()
        }
        Mock Write-Host {}
        $pc = [PSCustomObject]@{ Label = 'PC1'; Address = 'pc01' }
        $current = @([PSCustomObject]@{ Pc = $pc; Cluster = 'CL01'; ClusterExtId = 'c1'; UsedBytes = 9GB; LogicalUsedBytes = 18GB })
        function Write-TestHistory {
            param([object[]]$Rows)
            $Rows | Export-Csv -LiteralPath $testState.StorageFile -NoTypeInformation -UseCulture -Encoding utf8BOM
        }
    }

    It 'Does nothing without history' {
        ShowNxoStorageComparison -State $testState -Current $current
        Should -Invoke Write-Host -Times 0 -Exactly
    }

    It 'Says when there is no live run to compare with' {
        Write-TestHistory @([PSCustomObject]@{ TimeUtc = '2026-10-01T00:00:00Z'; RunId = 'r1'; Event = 'Measured'; PrismCentral = 'pc01'; ClusterExtId = 'c1'; UsedBytes = 10GB; LogicalUsedBytes = 20GB; DeletedCount = ''; FreedAtLeastBytes = '' })
        ShowNxoStorageComparison -State $testState -Current $current
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*No live run*' }
    }

    It 'Compares with the measurement before the first live run' {
        $time = [datetime]::UtcNow.AddDays(-2).ToString('yyyy-MM-ddTHH:mm:ssZ')
        Write-TestHistory @(
            [PSCustomObject]@{ TimeUtc = $time; RunId = 'r1'; Event = 'Measured'; PrismCentral = 'pc01'; ClusterExtId = 'c1'; UsedBytes = 10GB; LogicalUsedBytes = 20GB; DeletedCount = ''; FreedAtLeastBytes = '' }
            [PSCustomObject]@{ TimeUtc = $time; RunId = 'r1'; Event = 'Deleted'; PrismCentral = 'pc01'; ClusterExtId = ''; UsedBytes = ''; LogicalUsedBytes = ''; DeletedCount = '3'; FreedAtLeastBytes = [string]1GB }
        )
        ShowNxoStorageComparison -State $testState -Current $current
        Should -Invoke Write-Host -ParameterFilter { $Object -eq '  PC1 pc01: 3 recovery points deleted, expected to free at least 1.0 GiB' }
        Should -Invoke Write-Host -ParameterFilter { $Object -eq '    CL01: used storage down by 1.0 GiB (now 9.0 GiB), logical down by 2.0 GiB' }
        Get-Content -LiteralPath $testState.LogFile | Should -BeLike '*Storage change pc01 CL01 since r1*'
    }

    It 'Explains the Curator delay right after the deletion' {
        $time = [datetime]::UtcNow.AddMinutes(-30).ToString('yyyy-MM-ddTHH:mm:ssZ')
        Write-TestHistory @(
            [PSCustomObject]@{ TimeUtc = $time; RunId = 'r1'; Event = 'Measured'; PrismCentral = 'pc01'; ClusterExtId = 'c1'; UsedBytes = 9GB; LogicalUsedBytes = ''; DeletedCount = ''; FreedAtLeastBytes = '' }
            [PSCustomObject]@{ TimeUtc = $time; RunId = 'r1'; Event = 'Deleted'; PrismCentral = 'pc01'; ClusterExtId = ''; UsedBytes = ''; LogicalUsedBytes = ''; DeletedCount = '1'; FreedAtLeastBytes = '' }
        )
        ShowNxoStorageComparison -State $testState -Current $current
        Should -Invoke Write-Host -ParameterFilter { $Object -like 'Only 30 minutes since the deletion*' }
    }

    It 'Hints at Curator when nothing was freed after 36 hours' {
        $time = [datetime]::UtcNow.AddHours(-40).ToString('yyyy-MM-ddTHH:mm:ssZ')
        Write-TestHistory @(
            [PSCustomObject]@{ TimeUtc = $time; RunId = 'r1'; Event = 'Measured'; PrismCentral = 'pc01'; ClusterExtId = 'c1'; UsedBytes = 8GB; LogicalUsedBytes = ''; DeletedCount = ''; FreedAtLeastBytes = '' }
            [PSCustomObject]@{ TimeUtc = $time; RunId = 'r1'; Event = 'Deleted'; PrismCentral = 'pc01'; ClusterExtId = ''; UsedBytes = ''; LogicalUsedBytes = ''; DeletedCount = '1'; FreedAtLeastBytes = '' }
        )
        ShowNxoStorageComparison -State $testState -Current $current
        Should -Invoke Write-Host -ParameterFilter { $Object -like 'No decrease after 36 hours*' }
    }
}
