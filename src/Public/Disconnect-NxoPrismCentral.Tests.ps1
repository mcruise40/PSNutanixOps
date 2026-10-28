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

Describe 'Disconnect-NxoPrismCentral with a simulated Prism Central' {
    BeforeEach {
        . (Join-Path -Path $PSScriptRoot -ChildPath '../../tests/Helpers/FakePrismCentral.ps1')
        Reset-FakeNxoData
        $store = GetNxoConnectionStore
        $store.Clear()
        $store['pc01.example.local'] = New-TestConnection
        Mock InvokeNxoRestMethod { Invoke-FakeNxoRestMethod -Method $Method -Path $Path -Body $Body }
        Mock Start-Sleep {}
        Mock Write-Progress {}
    }

    AfterAll {
        (GetNxoConnectionStore).Clear()
    }
    Describe 'Disconnect-NxoPrismCentral' {
        BeforeEach {
            $store['pc02.example.local'] = New-TestConnection
            Mock Write-Warning {}
        }

        It 'Removes all connections without -Server' {
            Disconnect-NxoPrismCentral
            (GetNxoConnectionStore).Count | Should -Be 0
        }

        It 'Removes only the named connection' {
            Disconnect-NxoPrismCentral -Server 'https://PC02.example.local'
            @((GetNxoConnectionStore).Keys) | Should -Be @('pc01.example.local')
        }

        It 'Warns for an unknown server' {
            Disconnect-NxoPrismCentral -Server 'pc09'
            Should -Invoke Write-Warning -Times 1 -Exactly
            (GetNxoConnectionStore).Count | Should -Be 2
        }

        It 'Keeps all connections when an empty pipeline is piped in' {
            @() | Disconnect-NxoPrismCentral
            (GetNxoConnectionStore).Count | Should -Be 2
        }

        It 'Accepts connection objects from the pipeline' {
            [PSCustomObject]@{ Server = 'pc01.example.local' } | Disconnect-NxoPrismCentral
            @((GetNxoConnectionStore).Keys) | Should -Be @('pc02.example.local')
        }
    }
}
