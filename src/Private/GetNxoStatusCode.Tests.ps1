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

Describe 'GetNxoStatusCode' {
    It 'Reads the status code from Exception.Data' {
        GetNxoStatusCode -Exception (New-TestHttpError -StatusCode 404) | Should -Be 404
    }

    It 'Reads the status code from an inner exception' {
        $outer = [System.Exception]::new('outer', (New-TestHttpError -StatusCode 429))
        GetNxoStatusCode -Exception $outer | Should -Be 429
    }

    It 'Reads the status code from the HTTP response' {
        $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::Forbidden)
        $exception = [Microsoft.PowerShell.Commands.HttpResponseException]::new('forbidden', $response)
        GetNxoStatusCode -Exception $exception | Should -Be 403
    }

    It 'Returns $null without HTTP answer' {
        GetNxoStatusCode -Exception ([System.Exception]::new('DNS failure')) | Should -BeNullOrEmpty
    }

    It 'Accepts $null' {
        GetNxoStatusCode -Exception $null | Should -BeNullOrEmpty
    }
}
