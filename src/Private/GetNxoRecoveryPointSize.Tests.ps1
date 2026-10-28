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

Describe 'GetNxoRecoveryPointSize' {
    It 'Uses totalExclusiveUsageBytes' {
        GetNxoRecoveryPointSize -RecoveryPoint ([PSCustomObject]@{ totalExclusiveUsageBytes = 1024 }) | Should -Be 1024
    }

    It 'Sums the VM and volume group parts' {
        $rp = [PSCustomObject]@{
            vmRecoveryPoints          = @([PSCustomObject]@{ totalExclusiveUsageBytes = 100 }, [PSCustomObject]@{ totalExclusiveUsageBytes = $null })
            volumeGroupRecoveryPoints = @([PSCustomObject]@{ totalExclusiveUsageBytes = 50 })
        }
        GetNxoRecoveryPointSize -RecoveryPoint $rp | Should -Be 150
    }

    It 'Returns $null without size' {
        GetNxoRecoveryPointSize -RecoveryPoint ([PSCustomObject]@{ vmRecoveryPoints = @([PSCustomObject]@{ vmExtId = 'x' }) }) | Should -BeNullOrEmpty
        GetNxoRecoveryPointSize -RecoveryPoint $null | Should -BeNullOrEmpty
    }
}
