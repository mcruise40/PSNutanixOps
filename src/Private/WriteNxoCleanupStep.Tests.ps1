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

Describe 'WriteNxoCleanupStep' {
    BeforeEach {
        $testState = @{
            Mode = 'LIVE'; DryRun = $false; TotalSteps = 5; Stamp = '20261028-120000'
            LogFile = Join-Path -Path $TestDrive -ChildPath ('cleanup-{0}.log' -f [guid]::NewGuid())
            StorageFile = Join-Path -Path $TestDrive -ChildPath ('storage-history-{0}.csv' -f [guid]::NewGuid())
            Results = [System.Collections.Generic.List[object]]::new()
        }
        Mock Write-Host {}
    }

    It 'Shows and logs the step with the mode tag <Mode>' -TestCases @(
        @{ Mode = 'LIVE'; Tag = ' LIVE ' }
        @{ Mode = 'DRY RUN'; Tag = ' DRY RUN ' }
        @{ Mode = 'STORAGE REPORT'; Tag = ' STORAGE REPORT ' }
    ) {
        $testState.Mode = $Mode
        WriteNxoCleanupStep -State $testState -Number 2 -Title 'Collect'
        Should -Invoke Write-Host -ParameterFilter { $Object -eq '=== Step 2 of 5: Collect ' }
        Should -Invoke Write-Host -ParameterFilter { $Object -eq $Tag }
        Get-Content -LiteralPath $testState.LogFile | Should -BeLike '*Step 2: Collect'
    }

    It 'Shows only the mode tag without step number' {
        WriteNxoCleanupStep -State $testState
        Should -Invoke Write-Host -Times 1 -Exactly
        Test-Path -LiteralPath $testState.LogFile | Should -BeFalse
    }
}
