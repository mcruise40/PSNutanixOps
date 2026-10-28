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

Describe 'ResolveNxoNccCheck' {
    BeforeEach {
        $connection = New-TestConnection
    }

    It 'Resolves by extId and caches the result' {
        Mock InvokeNxoApi { [PSCustomObject]@{ data = [PSCustomObject]@{ title = 'Disk space'; kbArticles = @('KB1', $null, 'KB2') } } }
        $cache = @{}
        $result = ResolveNxoNccCheck -Connection $connection -CheckId '101061' -Cache $cache
        $result.Title | Should -Be 'Disk space'
        $result.Kb | Should -Be 'KB1, KB2'
        $null = ResolveNxoNccCheck -Connection $connection -CheckId '101061' -Cache $cache
        Should -Invoke InvokeNxoApi -Times 1 -Exactly
    }

    It 'Falls back to a policyId filter' {
        Mock InvokeNxoApi { throw 'not found' } -ParameterFilter { $Path -notlike '*$filter=*' }
        Mock InvokeNxoApi { [PSCustomObject]@{ data = @([PSCustomObject]@{ name = 'By name' }) } }
        (ResolveNxoNccCheck -Connection $connection -CheckId '42' -Cache @{}).Title | Should -Be 'By name'
    }

    It 'Returns no title when nothing is found' {
        Mock InvokeNxoApi { throw 'not found' }
        $result = ResolveNxoNccCheck -Connection $connection -CheckId '42' -Cache @{}
        $result.Title | Should -BeNullOrEmpty
        $result.Kb | Should -Be ''
    }
}
