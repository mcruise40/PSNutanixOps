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

Describe 'Get-NxoVmInventory with a simulated Prism Central' {
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
    Describe 'Get-NxoVmInventory' {
        It 'Returns one row per VM with resolved names' {
            $result = @(Get-NxoVmInventory)
            $result.VM | Should -Be @('APP01', 'OFF01', 'SQL01')
            $app = $result | Where-Object VM -EQ 'APP01'
            $app.PrismCentral | Should -Be 'pc01.example.local'
            $app.Cluster | Should -Be 'NTNX-CL01'
            $app.Host | Should -Be 'ntnx-h1'
            $app.vCPU | Should -Be 2
            $app.MemoryGB | Should -Be 4
            $app.DiskCount | Should -Be 2
            $app.DiskTotalGB | Should -Be 150
            $app.NGT_Installed | Should -BeTrue
            $app.NGT_UpdateNeeded | Should -BeTrue
            $app.BootType | Should -Be 'LegacyBoot'
            $app.MAC | Should -Be '50:6b:8d:aa:bb:cc'
            $app.IP | Should -Be '10.0.0.5'
            $app.Subnet | Should -Be 'VLAN100-Servers'
            $app.Categories | Should -Be 'Env:Prod, App:Citrix'
            $app.PSObject.TypeNames[0] | Should -Be 'PSNutanixOps.VmInventory'
        }

        It 'Handles VMs without NGT, disks and NICs' {
            $off = Get-NxoVmInventory | Where-Object VM -EQ 'OFF01'
            $off.NGT_Installed | Should -BeFalse
            $off.NGT_UpdateNeeded | Should -BeNullOrEmpty
            $off.DiskTotalGB | Should -BeNullOrEmpty
            $off.MAC | Should -BeNullOrEmpty
            $off.Host | Should -BeNullOrEmpty
        }

        It 'Filters by name, cluster and power state' {
            @(Get-NxoVmInventory -VmName 'app*', 'off01').VM | Should -Be @('APP01', 'OFF01')
            @(Get-NxoVmInventory -ClusterName 'ntnx-cl01' -ExcludePoweredOff).VM | Should -Be @('APP01', 'SQL01')
        }

        It 'Warns when nothing matches' {
            Mock Write-Warning {}
            Get-NxoVmInventory -VmName 'none' | Should -BeNullOrEmpty
            Should -Invoke Write-Warning -ParameterFilter { $Message -like 'No matching VMs*' }
        }

        It 'Skips a Prism Central whose VM list fails' {
            Mock InvokeNxoRestMethod { New-FakeNxoHttpError -StatusCode 500 }
            Mock Write-Warning {}
            Get-NxoVmInventory | Should -BeNullOrEmpty
            Should -Invoke Write-Warning -ParameterFilter { $Message -like 'Skipping Prism Central*' }
        }

        It 'Skips the cluster filter when cluster names cannot be resolved' {
            Mock GetNxoNameMap { @{} }
            Mock Write-Warning {}
            Get-NxoVmInventory -ClusterName 'NTNX-CL01' | Should -BeNullOrEmpty
            Should -Invoke Write-Warning -ParameterFilter { $Message -like '*cluster names could not be resolved*' }
        }

        It 'Throws without connection' {
            (GetNxoConnectionStore).Clear()
            { Get-NxoVmInventory } | Should -Throw '*Connect-NxoPrismCentral*'
        }
    }
}
