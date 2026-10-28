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

Describe 'ReadNxoJustification' {
    BeforeEach {
        Mock Write-Host {}
        $checks = @(
            [PSCustomObject]@{ Check = 'A'; Result = 'PASS'; Value = ''; Detail = ''; Justification = $null }
            [PSCustomObject]@{ Check = 'B'; Result = 'WARN'; Value = '1'; Detail = 'd'; Justification = $null }
            [PSCustomObject]@{ Check = 'C'; Result = 'WARN'; Value = '2'; Detail = 'd'; Justification = $null }
        )
    }

    It 'Stores the answers of the warnings' {
        $script:answers = [System.Collections.Generic.Queue[string]]::new([string[]]@('', 'known issue', 'fixed in 7.5'))
        Mock Read-Host { $script:answers.Dequeue() }
        ReadNxoJustification -Check $checks -ClusterName 'CL01'
        $checks[0].Justification | Should -BeNullOrEmpty
        $checks[1].Justification | Should -Be 'known issue'
        $checks[2].Justification | Should -Be 'fixed in 7.5'
    }

    It 'Marks warnings without answer' {
        Mock Read-Host { $null }
        ReadNxoJustification -Check $checks -ClusterName 'CL01'
        $checks[1].Justification | Should -Be '(no justification provided)'
        Should -Invoke Read-Host -Times 6 -Exactly
    }

    It 'Does not prompt with -NonInteractive' {
        Mock Read-Host { 'x' }
        ReadNxoJustification -Check $checks -ClusterName 'CL01' -NonInteractive
        $checks[2].Justification | Should -Be '(no justification provided)'
        Should -Invoke Read-Host -Times 0 -Exactly
    }
}
