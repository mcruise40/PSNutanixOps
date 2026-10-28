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

Describe 'ReadNxoText' {
    It 'Repeats until text is entered' {
        $script:answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('', '  ', ' pc01 '))
        Mock Read-Host { $script:answers.Dequeue() }
        ReadNxoText -Prompt 'Address' | Should -Be 'pc01'
        Should -Invoke Read-Host -Times 3 -Exactly
    }

    It 'Returns the default for an empty answer' {
        Mock Read-Host { '' }
        ReadNxoText -Prompt 'File' -Default 'list.csv' | Should -Be 'list.csv'
        Should -Invoke Read-Host -ParameterFilter { $Prompt -eq 'File [list.csv]' }
    }
}
