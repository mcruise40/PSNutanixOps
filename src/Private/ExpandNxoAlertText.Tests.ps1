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

Describe 'ExpandNxoAlertText' {
    It 'Fills typed and plain parameter values' {
        $parameters = @(
            [PSCustomObject]@{ paramName = 'vm_name'; paramValue = [PSCustomObject]@{ stringValue = 'SQL01' } }
            [PSCustomObject]@{ paramName = 'usage'; paramValue = [PSCustomObject]@{ intValue = 93 } }
            [PSCustomObject]@{ paramName = 'host'; paramValue = 'ntnx-h1' }
            [PSCustomObject]@{ paramName = 'flag'; paramValue = $null }
            $null
        )
        ExpandNxoAlertText -Text '{vm_name} on {host} at {usage} %{flag}' -Parameters $parameters | Should -Be 'SQL01 on ntnx-h1 at 93 %'
    }

    It 'Keeps unknown placeholders and empty texts' {
        ExpandNxoAlertText -Text 'value {x}' -Parameters @() | Should -Be 'value {x}'
        ExpandNxoAlertText -Text '' -Parameters $null | Should -Be ''
    }
}
