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

Describe 'ReadNxoYesNo' {
    It 'Interprets <Answer> as <Expected>' -TestCases @(
        @{ Answer = 'y'; Default = $false; Expected = $true }
        @{ Answer = 'JA'; Default = $false; Expected = $true }
        @{ Answer = 'no'; Default = $true; Expected = $false }
        @{ Answer = 'Nein'; Default = $true; Expected = $false }
        @{ Answer = ''; Default = $true; Expected = $true }
        @{ Answer = ''; Default = $false; Expected = $false }
    ) {
        Mock Read-Host { $Answer }
        ReadNxoYesNo -Prompt 'Continue?' -Default $Default | Should -Be $Expected
    }

    It 'Repeats on other answers and shows the default hint' {
        $script:answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('maybe', 'y'))
        Mock Read-Host { $script:answers.Dequeue() }
        ReadNxoYesNo -Prompt 'Continue?' -Default $false | Should -BeTrue
        Should -Invoke Read-Host -Times 2 -Exactly -ParameterFilter { $Prompt -eq 'Continue? [y/N]' }
    }
}
