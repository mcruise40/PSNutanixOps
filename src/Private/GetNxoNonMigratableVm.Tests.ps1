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

Describe 'GetNxoNonMigratableVm' {
    BeforeAll {
        $cluster = [PSCustomObject]@{ extId = '00000000-0000-0000-0000-00000000c1c1'; name = 'CL01' }
        $hosts = @([PSCustomObject]@{ extId = 'h-1'; hostName = 'ntnx-h1' })
        $running = @(
            [PSCustomObject]@{ name = 'GPU01'; isLiveMigrateCapable = $true; gpus = @([PSCustomObject]@{ mode = 'PASSTHROUGH_GRAPHICS' }); host = [PSCustomObject]@{ extId = 'h-1' } }
            [PSCustomObject]@{ name = 'PIN01'; isLiveMigrateCapable = $false; host = [PSCustomObject]@{ extId = 'h-x' } }
            [PSCustomObject]@{ name = 'OK01'; isLiveMigrateCapable = $true }
        )
    }
    BeforeEach {
        $connection = New-TestConnection
    }

    It 'Combines the AOS result with the VM properties' {
        Mock InvokeNxoApi { [PSCustomObject]@{ data = [PSCustomObject]@{ extId = 'task-1' } } } -ParameterFilter { $Method -eq 'POST' }
        Mock InvokeNxoApi { [PSCustomObject]@{ data = [PSCustomObject]@{ vms = @([PSCustomObject]@{ vmName = 'AFF01'; nonMigratableVmReason = 'VM-host affinity'; hostIp = [PSCustomObject]@{ ipv4 = [PSCustomObject]@{ value = '10.0.0.11' } } }, [PSCustomObject]@{ vmName = 'GPU01'; nonMigratableVmReason = 'GPU' }) } } }
        Mock WaitNxoTask { [PSCustomObject]@{ status = 'SUCCEEDED'; entitiesAffected = @([PSCustomObject]@{ extId = '11111111-2222-3333-4444-555555555555' }, [PSCustomObject]@{ extId = '00000000-0000-0000-0000-00000000c1c1' }) } }

        $result = GetNxoNonMigratableVm -Connection $connection -Cluster $cluster -HostList $hosts -RunningVm $running

        $result.Source | Should -BeLike 'AOS compute-non-migratable-vms*'
        @($result.Vm).VM | Should -Be @('AFF01', 'GPU01', 'PIN01')
        ($result.Vm | Where-Object VM -EQ 'PIN01').Reason | Should -BeLike '*VM property only*'
        Should -Invoke InvokeNxoApi -ParameterFilter { $Path -like '*/non-migratable-vms-result/11111111-2222-3333-4444-555555555555' }
    }

    It 'Uses only the VM properties when the action fails' {
        Mock InvokeNxoApi { throw 'not supported' }
        $result = GetNxoNonMigratableVm -Connection $connection -Cluster $cluster -HostList $hosts -RunningVm $running
        $result.Source | Should -BeLike 'VM properties*'
        @($result.Vm).VM | Should -Be @('GPU01', 'PIN01')
        ($result.Vm | Where-Object VM -EQ 'GPU01').Host | Should -Be 'ntnx-h1'
        ($result.Vm | Where-Object VM -EQ 'PIN01').Host | Should -Be 'h-x'
    }

    It 'Falls back when the task does not succeed' {
        Mock InvokeNxoApi { [PSCustomObject]@{ data = [PSCustomObject]@{ extId = 'task-1' } } }
        Mock WaitNxoTask { [PSCustomObject]@{ status = 'FAILED' } }
        (GetNxoNonMigratableVm -Connection $connection -Cluster $cluster -HostList $hosts -RunningVm @()).Vm.Count | Should -Be 0
    }
}
