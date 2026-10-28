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

Describe 'ResolveNxoDeletedVmName' {
    BeforeEach {
        $connection = New-TestConnection
        $rp = [PSCustomObject]@{ extId = 'rp-1'; vmRecoveryPoints = @([PSCustomObject]@{ extId = 'vmrp-1'; vmExtId = 'vm-gone' }) }
    }

    It 'Reads the name from the VM recovery point' {
        Mock InvokeNxoApi { [PSCustomObject]@{ data = [PSCustomObject]@{ vm = [PSCustomObject]@{ name = 'OLD-VM' } } } }
        ResolveNxoDeletedVmName -Connection $connection -RecoveryPoint $rp -VmExtId 'vm-gone' | Should -Be 'OLD-VM'
        Should -Invoke InvokeNxoApi -Times 1 -Exactly -ParameterFilter { $Path -eq '/ahv/config/vm-recovery-points/vmrp-1' }
    }

    It 'Tries the recovery point ID next' {
        Mock InvokeNxoApi { throw 'not found' } -ParameterFilter { $Path -like '*/vmrp-1' }
        Mock InvokeNxoApi { [PSCustomObject]@{ data = [PSCustomObject]@{ vm = [PSCustomObject]@{ name = 'FROM-RP' } } } }
        ResolveNxoDeletedVmName -Connection $connection -RecoveryPoint $rp -VmExtId 'vm-gone' | Should -Be 'FROM-RP'
    }

    It 'Returns a placeholder when nothing works' {
        Mock InvokeNxoApi { throw 'not found' }
        ResolveNxoDeletedVmName -Connection $connection -RecoveryPoint $rp -VmExtId '3d0b72d3-9525' | Should -Be '(name unknown, VM id 3d0b72d3)'
    }
}
