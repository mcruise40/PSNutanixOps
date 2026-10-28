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

Describe 'GetNxoTargetConnection' {
    BeforeEach {
        $store = GetNxoConnectionStore
        $store.Clear()
    }
    AfterAll {
        (GetNxoConnectionStore).Clear()
    }

    It 'Throws when nothing is connected' {
        { GetNxoTargetConnection } | Should -Throw '*Connect-NxoPrismCentral*'
    }

    It 'Returns all connections without -Server' {
        $store['a'] = [PSCustomObject]@{ Server = 'a' }
        $store['b'] = [PSCustomObject]@{ Server = 'b' }
        @(GetNxoTargetConnection).Server | Should -Be @('a', 'b')
    }

    It 'Returns only the named connection, normalized and without duplicates' {
        $store['pc01'] = [PSCustomObject]@{ Server = 'pc01' }
        $store['pc02'] = [PSCustomObject]@{ Server = 'pc02' }
        $result = @(GetNxoTargetConnection -Server 'https://PC02:9440', 'pc02')
        $result.Count | Should -Be 1
        $result[0].Server | Should -Be 'pc02'
    }

    It 'Throws for a server that is not connected' {
        $store['pc01'] = [PSCustomObject]@{ Server = 'pc01' }
        { GetNxoTargetConnection -Server 'pc09' } | Should -Throw "*'pc09'*"
    }
}
