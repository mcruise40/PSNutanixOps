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

Describe 'GetNxoPropertyValue' {
    It 'Reads an existing property' {
        GetNxoPropertyValue -InputObject ([PSCustomObject]@{ '$objectType' = 'vmm.v4.ahv.config.LegacyBoot' }) -Name '$objectType' | Should -Be 'vmm.v4.ahv.config.LegacyBoot'
    }

    It 'Returns $null for a missing property or object' {
        GetNxoPropertyValue -InputObject ([PSCustomObject]@{ a = 1 }) -Name 'b' | Should -BeNullOrEmpty
        GetNxoPropertyValue -InputObject $null -Name 'a' | Should -BeNullOrEmpty
    }
}
