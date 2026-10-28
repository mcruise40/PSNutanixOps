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

Describe 'ConvertToNxoUtcTime' {
    It 'Returns $null for <Case>' -TestCases @(
        @{ Case = 'null'; Value = $null }
        @{ Case = 'empty string'; Value = '' }
        @{ Case = 'whitespace'; Value = '  ' }
    ) {
        ConvertToNxoUtcTime -Timestamp $Value | Should -BeNullOrEmpty
    }

    It 'Parses an ISO string with Z' {
        $result = ConvertToNxoUtcTime -Timestamp '2026-10-12T14:18:16Z'
        $result.Kind | Should -Be 'Utc'
        $result | Should -Be ([datetime]::new(2026, 10, 12, 14, 18, 16, [System.DateTimeKind]::Utc))
    }

    It 'Converts an offset to UTC' {
        (ConvertToNxoUtcTime -Timestamp '2026-10-12T16:18:16+02:00').Hour | Should -Be 14
    }

    It 'Treats an Unspecified DateTime as UTC' {
        $value = [datetime]::new(2026, 1, 1, 8, 0, 0, [System.DateTimeKind]::Unspecified)
        $result = ConvertToNxoUtcTime -Timestamp $value
        $result.Kind | Should -Be 'Utc'
        $result.Hour | Should -Be 8
    }

    It 'Converts a local DateTime and a DateTimeOffset' {
        $local = [datetime]::new(2026, 1, 1, 8, 0, 0, [System.DateTimeKind]::Local)
        ConvertToNxoUtcTime -Timestamp $local | Should -Be $local.ToUniversalTime()
        ConvertToNxoUtcTime -Timestamp ([datetimeoffset]::new(2026, 1, 1, 8, 0, 0, [timespan]::FromHours(1))) | Should -Be ([datetime]::new(2026, 1, 1, 7, 0, 0, [System.DateTimeKind]::Utc))
    }
}
