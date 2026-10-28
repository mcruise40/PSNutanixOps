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

Describe 'GetNxoLookupState' {
    BeforeEach {
        $connection = New-TestConnection
    }

    It 'Returns Exists when the entity can be read' {
        Mock InvokeNxoApi { 'ok' }
        GetNxoLookupState -Connection $connection -Namespace vmm -Path '/ahv/config/vms/1' | Should -Be 'Exists'
    }

    It 'Returns Missing on 404' {
        Mock InvokeNxoApi { throw (New-TestHttpError -StatusCode 404) }
        GetNxoLookupState -Connection $connection -Namespace vmm -Path '/ahv/config/vms/1' | Should -Be 'Missing'
    }

    It 'Returns Unverified on other errors' {
        Mock InvokeNxoApi { throw (New-TestHttpError -StatusCode 403) }
        GetNxoLookupState -Connection $connection -Namespace vmm -Path '/ahv/config/vms/1' | Should -Be 'Unverified'
    }
}
