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

Describe 'GetNxoEntityState' {
    BeforeEach {
        $pcA = [PSCustomObject]@{ Label = 'PC1'; Connection = [PSCustomObject]@{ Server = 'a' }; EsxiListOk = $true; VgListOk = $true }
        $pcB = [PSCustomObject]@{ Label = 'PC2'; Connection = [PSCustomObject]@{ Server = 'b' }; EsxiListOk = $false; VgListOk = $false }
    }

    It 'Returns Exists when any Prism Central has the VM' {
        Mock GetNxoLookupState { if ($Connection.Server -eq 'b') { 'Exists' } else { 'Missing' } }
        GetNxoEntityState -Pc @($pcA, $pcB) -Kind Vm -ExtId 'vm-1' -HypervisorType 'AHV' | Should -Be 'Exists'
    }

    It 'Returns Missing only when every answer is not found' {
        Mock GetNxoLookupState { 'Missing' }
        GetNxoEntityState -Pc @($pcA, $pcB) -Kind Vm -ExtId 'vm-1' -HypervisorType 'AHV' | Should -Be 'Missing'
        Should -Invoke GetNxoLookupState -Times 3 -Exactly
        Should -Invoke GetNxoLookupState -Times 1 -Exactly -ParameterFilter { $Path -eq '/esxi/config/vms/vm-1' }
    }

    It 'Treats a non-AHV VM as unverified without ESXi list' {
        Mock GetNxoLookupState { 'Missing' }
        GetNxoEntityState -Pc @($pcB) -Kind Vm -ExtId 'vm-1' -HypervisorType 'ESX' | Should -Be 'Unverified'
    }

    It 'Trusts volume group lookups only where the list was readable' {
        Mock GetNxoLookupState { 'Missing' }
        GetNxoEntityState -Pc @($pcA) -Kind VolumeGroup -ExtId 'vg-1' | Should -Be 'Missing'
        GetNxoEntityState -Pc @($pcA, $pcB) -Kind VolumeGroup -ExtId 'vg-1' | Should -Be 'Unverified'
        Should -Invoke GetNxoLookupState -ParameterFilter { $Namespace -eq 'volumes' -and $Path -eq '/config/volume-groups/vg-1' }
    }
}
