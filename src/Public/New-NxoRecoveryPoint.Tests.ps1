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

Describe 'New-NxoRecoveryPoint with a simulated Prism Central' {
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
    Describe 'New-NxoRecoveryPoint' {
        It 'Creates one recovery point per VM and returns the results' {
            $result = @(New-NxoRecoveryPoint -VmName 'APP01', 'SQL01' -RecoveryPointName 'PrePatch' -RetentionDays 3 -Confirm:$false)
            $result.VM | Should -Be @('APP01', 'SQL01')
            $result.Status | Should -Be @('SUCCEEDED', 'SUCCEEDED')
            $result[0].Success | Should -BeTrue
            $result[0].Type | Should -Be 'CRASH_CONSISTENT'
            $result[0].PSObject.TypeNames[0] | Should -Be 'PSNutanixOps.RecoveryPointResult'
            Should -Invoke InvokeNxoRestMethod -Times 2 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Path -like '/dataprotection/*/config/recovery-points' -and $Body.name -eq 'PrePatch' -and @($Body.vmRecoveryPoints).Count -eq 1
            }
        }

        It 'Builds the app-consistent request with project' {
            $null = New-NxoRecoveryPoint -VmName 'SQL01' -AppConsistent -ProjectExtId 'proj-1' -Confirm:$false
            Should -Invoke InvokeNxoRestMethod -Times 1 -Exactly -ParameterFilter {
                $Method -eq 'POST' -and $Body.recoveryPointType -eq 'APPLICATION_CONSISTENT' -and $Body.projectExtId -eq 'proj-1' -and
                $Body.vmRecoveryPoints[0].applicationConsistentProperties.backupType -eq 'FULL_BACKUP'
            }
        }

        It 'Accepts VM names from the pipeline by property name' {
            $result = @([PSCustomObject]@{ VM = 'SQL01'; PrismCentral = 'pc01.example.local' } | New-NxoRecoveryPoint -Confirm:$false)
            $result.VM | Should -Be @('SQL01')
        }

        It 'Selects VMs by category' {
            @(New-NxoRecoveryPoint -CategoryKey 'Workload' -CategoryValue 'SQL' -Confirm:$false).VM | Should -Be @('SQL01')
        }

        It 'Creates nothing under -WhatIf' {
            New-NxoRecoveryPoint -VmName 'SQL01' -WhatIf | Should -BeNullOrEmpty
            Should -Invoke InvokeNxoRestMethod -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' }
        }

        It 'Warns about unknown VMs' {
            Mock Write-Warning {}
            New-NxoRecoveryPoint -VmName 'none' -Confirm:$false | Should -BeNullOrEmpty
            Should -Invoke Write-Warning -ParameterFilter { $Message -like "VM 'none' not found*" }
        }

        It 'Reports failed and unfinished tasks' {
            Mock Write-Warning {}
            Mock WaitNxoTask { [PSCustomObject]@{ status = 'FAILED'; errorMessages = @([PSCustomObject]@{ message = 'DP-10100' }) } }
            $failed = New-NxoRecoveryPoint -VmName 'SQL01' -Confirm:$false
            $failed.Status | Should -Be 'FAILED'
            $failed.Message | Should -Be 'DP-10100'

            Mock WaitNxoTask { [PSCustomObject]@{ status = 'RUNNING' } }
            (New-NxoRecoveryPoint -VmName 'SQL01' -Confirm:$false).Status | Should -Be 'TIMEOUT'
        }

        It 'Reports API errors per VM and continues' {
            Mock Write-Warning {}
            Mock InvokeNxoApi { throw 'quota exceeded' } -ParameterFilter { $Method -eq 'POST' }
            $result = @(New-NxoRecoveryPoint -VmName 'APP01', 'SQL01' -Confirm:$false)
            $result.Count | Should -Be 2
            $result[0].Success | Should -BeFalse
            $result[0].Message | Should -BeLike '*quota exceeded*'
        }
    }
}
