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

Describe 'GetNxoVmNetworkInfo' {
    It 'Reads the v4.1+ NIC structures' {
        $vm = [PSCustomObject]@{ nics = @(
                [PSCustomObject]@{
                    nicBackingInfo = [PSCustomObject]@{ macAddress = '50:6b:8d:aa:bb:cc' }
                    nicNetworkInfo = [PSCustomObject]@{
                        subnet     = [PSCustomObject]@{ extId = 'sn-1' }
                        ipv4Config = [PSCustomObject]@{
                            ipAddress              = [PSCustomObject]@{ value = '10.0.0.5' }
                            secondaryIpAddressList = @([PSCustomObject]@{ value = '10.0.0.50' })
                        }
                        ipv4Info   = [PSCustomObject]@{ learnedIpAddresses = @([PSCustomObject]@{ value = '10.0.0.5' }) }
                    }
                }
            ) }
        $result = GetNxoVmNetworkInfo -Vm $vm
        $result.MacAddress | Should -Be @('50:6b:8d:aa:bb:cc')
        $result.SubnetExtId | Should -Be @('sn-1')
        $result.IpAddress | Should -Be @('10.0.0.5', '10.0.0.50', '10.0.0.5')
    }

    It 'Falls back to the legacy NIC structures' {
        $vm = [PSCustomObject]@{ nics = @(
                [PSCustomObject]@{
                    backingInfo = [PSCustomObject]@{ macAddress = 'aa:bb' }
                    networkInfo = [PSCustomObject]@{ ipv4Info = [PSCustomObject]@{ learnedIpAddresses = @([PSCustomObject]@{ value = '10.0.0.9' }) } }
                }
                [PSCustomObject]@{ backingInfo = [PSCustomObject]@{ macAddress = 'cc:dd' } }
            ) }
        $result = GetNxoVmNetworkInfo -Vm $vm
        $result.MacAddress | Should -Be @('aa:bb', 'cc:dd')
        $result.IpAddress | Should -Be @('10.0.0.9')
        $result.SubnetExtId.Count | Should -Be 0
    }

    It 'Returns empty arrays for a VM without NICs' {
        $result = GetNxoVmNetworkInfo -Vm ([PSCustomObject]@{ name = 'x' })
        $result.MacAddress.Count + $result.IpAddress.Count + $result.SubnetExtId.Count | Should -Be 0
    }
}
