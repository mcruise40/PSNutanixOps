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

Describe 'ConvertToNxoStorageRow' {
    BeforeEach {
        $testState = @{
            Mode = 'LIVE'; DryRun = $false; TotalSteps = 5; Stamp = '20261028-120000'
            LogFile = Join-Path -Path $TestDrive -ChildPath ('cleanup-{0}.log' -f [guid]::NewGuid())
            StorageFile = Join-Path -Path $TestDrive -ChildPath ('storage-history-{0}.csv' -f [guid]::NewGuid())
            Results = [System.Collections.Generic.List[object]]::new()
        }
    }

    It 'Builds a Measured row' {
        $measurement = [PSCustomObject]@{ Cluster = 'CL01'; ClusterExtId = 'c1'; UsedBytes = 1; LogicalUsedBytes = 2; CapacityBytes = 3 }
        $row = ConvertToNxoStorageRow -State $testState -EventName Measured -PrismCentral 'pc01' -Measurement $measurement
        $row.RunId | Should -Be '20261028-120000'
        $row.Mode | Should -Be 'LIVE'
        $row.Cluster | Should -Be 'CL01'
        $row.DeletedCount | Should -BeNullOrEmpty
        $row.TimeUtc | Should -Match '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$'
    }

    It 'Builds a Deleted row' {
        $row = ConvertToNxoStorageRow -State $testState -EventName Deleted -PrismCentral 'pc01' -DeletedCount 4 -FreedAtLeastBytes 1GB
        $row.DeletedCount | Should -Be 4
        $row.FreedAtLeastBytes | Should -Be 1GB
        $row.Cluster | Should -BeNullOrEmpty
    }
}
