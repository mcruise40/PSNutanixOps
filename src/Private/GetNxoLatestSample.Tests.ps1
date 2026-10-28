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

Describe 'GetNxoLatestSample' {
    It 'Returns the newest sample with a value' {
        $series = @(
            [PSCustomObject]@{ timestamp = '2026-10-28T10:00:00Z'; value = 1 }
            [PSCustomObject]@{ timestamp = '2026-10-28T12:00:00Z'; value = 3 }
            [PSCustomObject]@{ timestamp = '2026-10-28T13:00:00Z'; value = $null }
            [PSCustomObject]@{ timestamp = '2026-10-28T11:00:00Z'; value = 2 }
        )
        (GetNxoLatestSample -Series $series).value | Should -Be 3
    }

    It 'Returns $null for an empty series' {
        GetNxoLatestSample -Series @() | Should -BeNullOrEmpty
        GetNxoLatestSample -Series $null | Should -BeNullOrEmpty
    }
}
