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

Describe 'JoinNxoUnique' {
    It 'Joins distinct values in order of first appearance' {
        JoinNxoUnique -Value @('10.0.0.5', $null, '10.0.0.5', '', '10.0.0.6') | Should -Be '10.0.0.5, 10.0.0.6'
    }

    It 'Compares case-insensitively and uses the separator' {
        JoinNxoUnique -Value @('AA:BB', 'aa:bb', 'cc') -Separator ';' | Should -Be 'AA:BB;cc'
    }

    It 'Returns $null when nothing is left' {
        JoinNxoUnique -Value @($null, ' ') | Should -BeNullOrEmpty
        JoinNxoUnique -Value @() | Should -BeNullOrEmpty
    }
}
