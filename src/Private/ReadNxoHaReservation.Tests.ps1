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

Describe 'ReadNxoHaReservation' {
    BeforeEach {
        Mock Write-Host {}
    }

    It 'Returns the first letter of a valid answer' {
        Mock Read-Host { 'yes' }
        ReadNxoHaReservation -ClusterName 'CL01' -UiPath 'Settings' | Should -Be 'Y'
    }

    It 'Asks up to three times' {
        Mock Read-Host { 'maybe' }
        ReadNxoHaReservation -ClusterName 'CL01' -UiPath 'Settings' | Should -BeNullOrEmpty
        Should -Invoke Read-Host -Times 3 -Exactly
    }

    It 'Does not prompt with -NonInteractive' {
        Mock Read-Host { 'y' }
        ReadNxoHaReservation -ClusterName 'CL01' -UiPath 'Settings' -NonInteractive | Should -BeNullOrEmpty
        Should -Invoke Read-Host -Times 0 -Exactly
    }
}
