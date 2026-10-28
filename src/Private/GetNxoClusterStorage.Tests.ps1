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

Describe 'GetNxoClusterStorage' {
    It 'Returns the latest storage values per cluster' {
        $pc = [PSCustomObject]@{ Label = 'PC1'; Address = 'pc01'; Connection = (New-TestConnection) }
        Mock GetNxoClusterList { [PSCustomObject]@{ extId = 'c1'; name = 'CL01' }; [PSCustomObject]@{ extId = '3d0b72d3-9525'; name = $null } }
        Mock GetNxoStatSeries {
            @{
                storageUsageBytes        = @([PSCustomObject]@{ timestamp = '2026-10-28T10:00:00Z'; value = 100 }, [PSCustomObject]@{ timestamp = '2026-10-28T11:00:00Z'; value = 200 })
                logicalStorageUsageBytes = @()
                storageCapacityBytes     = @([PSCustomObject]@{ timestamp = '2026-10-28T11:00:00Z'; value = 1000 })
            }
        }
        $result = @(GetNxoClusterStorage -Pc $pc)
        $result.Count | Should -Be 2
        $result[0].Cluster | Should -Be 'CL01'
        $result[0].UsedBytes | Should -Be 200
        $result[0].LogicalUsedBytes | Should -BeNullOrEmpty
        $result[0].CapacityBytes | Should -Be 1000
        $result[1].Cluster | Should -Be '3d0b72d3'
        Should -Invoke GetNxoStatSeries -ParameterFilter { $StatType -eq 'LAST' -and $NoSelect -and $Path -eq '/stats/clusters/c1' }
    }
}
