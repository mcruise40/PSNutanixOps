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

Describe 'AddNxoStorageHistory' {
    BeforeEach {
        $testState = @{
            Mode = 'LIVE'; DryRun = $false; TotalSteps = 5; Stamp = '20261028-120000'
            LogFile = Join-Path -Path $TestDrive -ChildPath ('cleanup-{0}.log' -f [guid]::NewGuid())
            StorageFile = Join-Path -Path $TestDrive -ChildPath ('storage-history-{0}.csv' -f [guid]::NewGuid())
            Results = [System.Collections.Generic.List[object]]::new()
        }
    }

    It 'Appends rows to the history file' {
        AddNxoStorageHistory -State $testState -Row @([PSCustomObject]@{ A = 1 })
        AddNxoStorageHistory -State $testState -Row @([PSCustomObject]@{ A = 2 })
        @(Import-Csv -LiteralPath $testState.StorageFile -UseCulture).A | Should -Be @('1', '2')
    }

    It 'Does nothing without rows' {
        AddNxoStorageHistory -State $testState -Row @()
        Test-Path -LiteralPath $testState.StorageFile | Should -BeFalse
    }

    It 'Reports write errors without stopping' {
        Mock Export-Csv { throw 'locked' }
        Mock Write-Host {}
        { AddNxoStorageHistory -State $testState -Row @([PSCustomObject]@{ A = 1 }) } | Should -Not -Throw
        Get-Content -LiteralPath $testState.LogFile | Should -Match '\[WARN\] Storage history could not be written'
    }
}
