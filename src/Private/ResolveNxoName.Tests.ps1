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

Describe 'ResolveNxoName' {
    It 'Resolves known IDs and falls back to the ID' {
        $map = @{ 'cl-1' = 'NTNX-CL01'; 'cl-2' = '' }
        ResolveNxoName -Map $map -ExtId 'cl-1' | Should -Be 'NTNX-CL01'
        ResolveNxoName -Map $map -ExtId 'cl-2' | Should -Be 'cl-2'
        ResolveNxoName -Map $map -ExtId 'cl-9' | Should -Be 'cl-9'
        ResolveNxoName -Map $null -ExtId 'cl-9' | Should -Be 'cl-9'
    }

    It 'Returns $null for an empty ID' {
        ResolveNxoName -Map @{} -ExtId '' | Should -BeNullOrEmpty
        ResolveNxoName -Map @{} -ExtId $null | Should -BeNullOrEmpty
    }
}
