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

Describe 'Connect-NxoPrismCentral with a simulated Prism Central' {
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
    Describe 'Connect-NxoPrismCentral' {
        BeforeEach {
            (GetNxoConnectionStore).Clear()
        }

        It 'Stores the connection and returns the view' {
            $result = Connect-NxoPrismCentral -Server 'https://PC02.example.local:9440/' -Credential $testCredential -SkipCertificateCheck
            $result.Server | Should -Be 'pc02.example.local'
            $result.UserName | Should -Be 'admin'
            $result.PSObject.Properties.Name | Should -Not -Contain 'Credential'
            $stored = (GetNxoConnectionStore)['pc02.example.local']
            $stored.SkipCertificateCheck | Should -BeTrue
            $stored.NamespaceVersion['vmm@v4.2'] | Should -Be 'v4.2'
        }

        It 'Accepts several servers from the pipeline and the PcIp alias' {
            @('pc02', 'pc03' | Connect-NxoPrismCentral -Credential $testCredential).Count | Should -Be 2
            @(Connect-NxoPrismCentral -PcIp 'pc04' -Credential $testCredential).Count | Should -Be 1
            (GetNxoConnectionStore).Count | Should -Be 3
        }

        It 'Writes an error for <Case>' -TestCases @(
            @{ Case = 'wrong password'; Code = 401; Expected = '*wrong user name or password*' }
            @{ Case = 'missing permission'; Code = 403; Expected = '*may not read VMs*' }
            @{ Case = 'missing v4 API'; Code = 404; Expected = '*v4 API is not available*' }
            @{ Case = 'server error'; Code = 500; Expected = '*failed (500)*' }
        ) {
            Mock InvokeNxoRestMethod { New-FakeNxoHttpError -StatusCode $Code -Message 'failed' }
            $result = Connect-NxoPrismCentral -Server 'pc02' -Credential $testCredential -ErrorVariable connectError -ErrorAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            # -ErrorVariable also collects the errors caught inside the command; the last one is the reported error.
            $connectError[-1].Exception.Message | Should -BeLike $Expected
            $connectError[-1].FullyQualifiedErrorId | Should -BeLike 'NxoConnectFailed*'
            (GetNxoConnectionStore).Count | Should -Be 0
        }

        It 'Hints at -SkipCertificateCheck on certificate errors' {
            Mock InvokeNxoRestMethod { throw [System.Exception]::new('The SSL connection could not be established') }
            Connect-NxoPrismCentral -Server 'pc02' -Credential $testCredential -ErrorVariable connectError -ErrorAction SilentlyContinue
            $connectError[-1].Exception.Message | Should -BeLike '*use -SkipCertificateCheck*'
        }

        It 'Validates the API version' {
            { Connect-NxoPrismCentral -Server 'pc02' -Credential $testCredential -ApiVersion '4.2' } | Should -Throw
        }
    }
}
