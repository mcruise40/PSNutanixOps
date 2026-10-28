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

Describe 'FormatNxoSize' {
    It 'Formats <Bytes> as <Expected>' -TestCases @(
        @{ Bytes = 0; Unit = 'Auto'; Expected = '0 B' }
        @{ Bytes = 512; Unit = 'Auto'; Expected = '512 B' }
        @{ Bytes = 1536; Unit = 'Auto'; Expected = '1.5 KiB' }
        @{ Bytes = 1610612736; Unit = 'Auto'; Expected = '1.5 GiB' }
        @{ Bytes = 5TB; Unit = 'Auto'; Expected = '5.0 TiB' }
        @{ Bytes = 2PB; Unit = 'Auto'; Expected = '2.0 PiB' }
        @{ Bytes = 549755813888; Unit = 'GiB'; Expected = '512 GiB' }
        @{ Bytes = 5497558138880; Unit = 'TiB'; Expected = '5.00 TiB' }
    ) {
        FormatNxoSize -Bytes $Bytes -Unit $Unit | Should -Be $Expected
    }

    It 'Returns n/a for $null' {
        FormatNxoSize -Bytes $null | Should -Be 'n/a'
    }

    It 'Rejects unknown units' {
        { FormatNxoSize -Bytes 1 -Unit 'MB' } | Should -Throw
    }
}
