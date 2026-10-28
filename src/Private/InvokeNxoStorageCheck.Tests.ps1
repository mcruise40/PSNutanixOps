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

Describe 'InvokeNxoStorageCheck' {
    BeforeEach {
        $testState = @{
            Mode = 'LIVE'; DryRun = $false; TotalSteps = 5; Stamp = '20261028-120000'
            LogFile = Join-Path -Path $TestDrive -ChildPath ('cleanup-{0}.log' -f [guid]::NewGuid())
            StorageFile = Join-Path -Path $TestDrive -ChildPath ('storage-history-{0}.csv' -f [guid]::NewGuid())
            Results = [System.Collections.Generic.List[object]]::new()
        }
        Mock Write-Host {}
        Mock ShowNxoStorageComparison {}
        $pcs = @([PSCustomObject]@{ Label = 'PC1'; Address = 'pc01' }, [PSCustomObject]@{ Label = 'PC2'; Address = 'pc02' })
    }

    It 'Shows, records and compares the storage' {
        Mock GetNxoClusterStorage {
            if ($Pc.Label -eq 'PC2') { throw 'stats not available' }
            [PSCustomObject]@{ Pc = $Pc; Cluster = 'CL01'; ClusterExtId = 'c1'; UsedBytes = 1GB; LogicalUsedBytes = 2GB; CapacityBytes = 10GB }
        }
        InvokeNxoStorageCheck -State $testState -Pc $pcs
        Should -Invoke Write-Host -ParameterFilter { $Object -eq '  PC1 CL01: used 1.0 GiB of 10.0 GiB, logical 2.0 GiB' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like '*PC2: storage usage could not be read (stats not available)*' }
        @(Import-Csv -LiteralPath $testState.StorageFile -UseCulture).Event | Should -Be @('Measured')
        Should -Invoke ShowNxoStorageComparison -Times 1 -Exactly
    }

    It 'Stops quietly without measurements' {
        Mock GetNxoClusterStorage {}
        InvokeNxoStorageCheck -State $testState -Pc $pcs
        Should -Invoke ShowNxoStorageComparison -Times 0 -Exactly
    }
}
