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

Describe 'Remove-NxoRecoveryPoint with a simulated Prism Central' {
    BeforeEach {
        . (Join-Path -Path $PSScriptRoot -ChildPath '../../tests/Helpers/FakePrismCentral.ps1')
        Reset-FakeNxoData
        $store = GetNxoConnectionStore
        $store.Clear()
        $store['pc01.example.local'] = New-TestConnection
        Mock InvokeNxoRestMethod { Invoke-FakeNxoRestMethod -Method $Method -Path $Path -Body $Body }
        Mock Start-Sleep {}
        Mock Write-Progress {}
    }

    AfterAll {
        (GetNxoConnectionStore).Clear()
    }
    Describe 'Remove-NxoRecoveryPoint' {
        It 'Deletes a recovery point and shows its VM' {
            $result = Remove-NxoRecoveryPoint -ExtId 'rp-1' -Confirm:$false
            $result.Status | Should -Be 'SUCCEEDED'
            $result.RecoveryPointName | Should -Be 'OnDemand-1'
            $result.VMs | Should -Be 'APP01'
            $script:FakeNxoData.Rps.extId | Should -Not -Contain 'rp-1'
        }

        It 'Accepts the output of Get-NxoRecoveryPoint' {
            $result = @(Get-NxoRecoveryPoint -VmName 'SQL01' | Remove-NxoRecoveryPoint -Confirm:$false)
            $result.ExtId | Should -Be @('rp-3')
            $result.PrismCentral | Should -Be @('pc01.example.local')
        }

        It 'Deletes nothing under -WhatIf' {
            Remove-NxoRecoveryPoint -ExtId 'rp-1' -WhatIf | Should -BeNullOrEmpty
            $script:FakeNxoData.Rps.extId | Should -Contain 'rp-1'
        }

        It 'Writes an error when the recovery point is on no Prism Central' {
            $store['pc02.example.local'] = New-TestConnection
            $store['pc02.example.local'].Server = 'pc02.example.local'
            Remove-NxoRecoveryPoint -ExtId 'rp-9' -Confirm:$false -ErrorVariable removeError -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
            $removeError[-1].FullyQualifiedErrorId | Should -BeLike 'NxoRecoveryPointNotFound*'
        }

        It 'Tries the deletion on a single Prism Central and reports the failure' {
            Mock Write-Warning {}
            $result = Remove-NxoRecoveryPoint -ExtId 'rp-9' -Confirm:$false
            $result.Success | Should -BeFalse
            $result.Message | Should -BeLike '*404*'
        }

        It 'Reports failed and unfinished tasks' {
            Mock Write-Warning {}
            Mock WaitNxoTask { [PSCustomObject]@{ status = 'FAILED'; errorMessages = @([PSCustomObject]@{ message = 'secure recovery point' }) } }
            (Remove-NxoRecoveryPoint -ExtId 'rp-1' -Confirm:$false).Message | Should -Be 'secure recovery point'
            Mock WaitNxoTask { [PSCustomObject]@{ status = 'QUEUED' } }
            (Remove-NxoRecoveryPoint -ExtId 'rp-2' -Confirm:$false).Status | Should -Be 'TIMEOUT'
        }
    }
}
