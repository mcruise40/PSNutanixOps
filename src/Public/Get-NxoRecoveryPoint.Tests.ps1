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

Describe 'Get-NxoRecoveryPoint with a simulated Prism Central' {
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
    Describe 'Get-NxoRecoveryPoint' {
        It 'Lists all recovery points, newest first, with VM names' {
            $result = @(Get-NxoRecoveryPoint)
            $result.ExtId | Should -Be @('rp-3', 'rp-1', 'rp-2')
            ($result | Where-Object ExtId -EQ 'rp-1').VMs | Should -Be 'APP01'
            ($result | Where-Object ExtId -EQ 'rp-2').VMs | Should -Be 'vm-gone'
            $result[0].PrismCentral | Should -Be 'pc01.example.local'
            $result[0].PSObject.TypeNames[0] | Should -Be 'PSNutanixOps.RecoveryPoint'
        }

        It 'Filters by VM name' {
            @(Get-NxoRecoveryPoint -VmName 'sql*').ExtId | Should -Be @('rp-3')
            Get-NxoRecoveryPoint -VmName 'none' | Should -BeNullOrEmpty
        }

        It 'Filters by category' {
            @(Get-NxoRecoveryPoint -CategoryKey 'Env' -CategoryValue 'Prod').ExtId | Should -Be @('rp-1')
            Mock Write-Warning {}
            Get-NxoRecoveryPoint -CategoryKey 'Env' -CategoryValue 'Test' | Should -BeNullOrEmpty
        }

        It 'Returns the raw objects with -Raw' {
            $raw = @(Get-NxoRecoveryPoint -Raw)
            $raw.Count | Should -Be 3
            $raw[0].vmRecoveryPoints | Should -Not -BeNullOrEmpty
        }

        It 'Skips a Prism Central that fails' {
            Mock InvokeNxoRestMethod { New-FakeNxoHttpError -StatusCode 500 }
            Mock Write-Warning {}
            Get-NxoRecoveryPoint | Should -BeNullOrEmpty
        }
    }
}
