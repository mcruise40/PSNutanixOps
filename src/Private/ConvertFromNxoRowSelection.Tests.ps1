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

Describe 'ConvertFromNxoRowSelection' {
    It 'Parses <Text>' -TestCases @(
        @{ Text = '1,4,7-9'; Expected = @(1, 4, 7, 8, 9) }
        @{ Text = '3 1;2'; Expected = @(1, 2, 3) }
        @{ Text = '5-3, 4'; Expected = @(3, 4, 5) }
    ) {
        @(ConvertFromNxoRowSelection -Text $Text -Max 10) | Should -Be $Expected
    }

    It 'Returns nothing for <Text>' -TestCases @(
        @{ Text = 'all' }
        @{ Text = '0' }
        @{ Text = '1-11' }
        @{ Text = '' }
        @{ Text = '1,x' }
    ) {
        @(ConvertFromNxoRowSelection -Text $Text -Max 10).Count | Should -Be 0
    }
}
