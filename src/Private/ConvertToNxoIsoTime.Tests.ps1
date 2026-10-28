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

Describe 'ConvertToNxoIsoTime' {
    It 'Formats UTC with Z' {
        ConvertToNxoIsoTime -Date ([datetime]::new(2026, 3, 4, 5, 6, 7, [System.DateTimeKind]::Utc)) | Should -Be '2026-03-04T05:06:07Z'
    }

    It 'Converts local time to UTC' {
        $local = [datetime]::new(2026, 3, 4, 5, 6, 7, [System.DateTimeKind]::Local)
        ConvertToNxoIsoTime -Date $local | Should -Be $local.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
}
