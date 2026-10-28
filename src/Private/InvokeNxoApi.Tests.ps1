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

Describe 'InvokeNxoApi' {
    BeforeEach {
        $connection = New-TestConnection
    }

    It 'Uses the connection API version first and caches it' {
        Mock InvokeNxoRestMethod { [PSCustomObject]@{ data = $Path } }

        (InvokeNxoApi -Connection $connection -Namespace vmm -Path '/ahv/config/vms').data | Should -Be '/vmm/v4.2/ahv/config/vms'
        $connection.NamespaceVersion['vmm@v4.2'] | Should -Be 'v4.2'
    }

    It 'Falls back to the next revision on 404' {
        Mock InvokeNxoRestMethod { throw (New-TestHttpError -StatusCode 404) } -ParameterFilter { $Path -like '/clustermgmt/v4.3/*' }
        Mock InvokeNxoRestMethod { [PSCustomObject]@{ data = $Path } }

        $result = InvokeNxoApi -Connection $connection -Namespace clustermgmt -Path '/config/clusters' -PreferVersion 'v4.3'

        $result.data | Should -Be '/clustermgmt/v4.2/config/clusters'
        $connection.NamespaceVersion['clustermgmt@v4.3'] | Should -Be 'v4.2'
    }

    It 'Uses a cached revision directly' {
        $connection.NamespaceVersion['vmm@v4.2'] = 'v4.0'
        Mock InvokeNxoRestMethod { [PSCustomObject]@{ data = $Path } }

        (InvokeNxoApi -Connection $connection -Namespace vmm -Path '/x').data | Should -Be '/vmm/v4.0/x'
        Should -Invoke InvokeNxoRestMethod -Times 1 -Exactly
    }

    It 'Does not try other revisions on other errors' {
        Mock InvokeNxoRestMethod { throw (New-TestHttpError -StatusCode 401) }

        { InvokeNxoApi -Connection $connection -Namespace vmm -Path '/x' } | Should -Throw
        Should -Invoke InvokeNxoRestMethod -Times 1 -Exactly
    }

    It 'Throws the last error when no revision works' {
        Mock InvokeNxoRestMethod { throw (New-TestHttpError -StatusCode 404 -Message 'nope') }

        { InvokeNxoApi -Connection $connection -Namespace vmm -Path '/x' } | Should -Throw '*nope*'
        Should -Invoke InvokeNxoRestMethod -Times 4 -Exactly
    }

    It 'Uses exactly -Version without caching' {
        Mock InvokeNxoRestMethod { throw (New-TestHttpError -StatusCode 404) }

        { InvokeNxoApi -Connection $connection -Namespace vmm -Path '/x' -Version 'v4.1' } | Should -Throw
        Should -Invoke InvokeNxoRestMethod -Times 1 -Exactly -ParameterFilter { $Path -eq '/vmm/v4.1/x' }
        $connection.NamespaceVersion.Count | Should -Be 0
    }

    It 'Passes method and body' {
        Mock InvokeNxoRestMethod { 'ok' }
        $null = InvokeNxoApi -Connection $connection -Namespace prism -Path '/x' -Method POST -Body @{ a = 1 }
        Should -Invoke InvokeNxoRestMethod -ParameterFilter { $Method -eq 'POST' -and $Body.a -eq 1 }
    }
}
