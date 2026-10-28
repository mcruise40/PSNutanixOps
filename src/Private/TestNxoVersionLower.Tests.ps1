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

Describe 'TestNxoVersionLower' {
    It 'Compares <Installed> with <Available>' -TestCases @(
        @{ Installed = '4.3.1'; Available = '4.5.1.8'; Expected = $true }
        @{ Installed = '4.5.1.8'; Available = '4.5.1.8'; Expected = $false }
        @{ Installed = '4.10'; Available = '4.9'; Expected = $false }
        @{ Installed = '4.3-beta'; Available = '4.3'; Expected = $true }
        @{ Installed = '4.3'; Available = '4.3 '; Expected = $false }
    ) {
        TestNxoVersionLower -Installed $Installed -Available $Available | Should -Be $Expected
    }

    It 'Returns $null when a version is missing' {
        TestNxoVersionLower -Installed $null -Available '4.5' | Should -BeNullOrEmpty
        TestNxoVersionLower -Installed '4.5' -Available '' | Should -BeNullOrEmpty
    }
}
