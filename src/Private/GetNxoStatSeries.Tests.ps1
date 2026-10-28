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

Describe 'GetNxoStatSeries' {
    BeforeEach {
        $connection = New-TestConnection
        $param = @{
            Connection = $connection; Path = '/stats/clusters/c1'; Field = @('hypervisorCpuUsagePpm', 'storageUsageBytes')
            StartTime = [datetime]'2026-10-01T00:00:00Z'; EndTime = [datetime]'2026-10-02T00:00:00Z'; StatType = 'MAX'
        }
    }

    It 'Uses $select and reads the metric arrays' {
        Mock InvokeNxoApi {
            [PSCustomObject]@{ data = [PSCustomObject]@{
                    hypervisorCpuUsagePpm = @([PSCustomObject]@{ timestamp = 't1'; value = 5 }, [PSCustomObject]@{ timestamp = 't2'; value = $null })
                } }
        }
        $result = GetNxoStatSeries @param
        @($result['hypervisorCpuUsagePpm']).Count | Should -Be 1
        @($result['storageUsageBytes']).Count | Should -Be 0
        Should -Invoke InvokeNxoApi -Times 1 -Exactly -ParameterFilter {
            $Namespace -eq 'clustermgmt' -and $Path -like '/stats/clusters/c1?$startTime=*&$statType=MAX&$select=hypervisorCpuUsagePpm%2CstorageUsageBytes'
        }
    }

    It 'Retries without $select and reads the tuple shape' {
        Mock InvokeNxoApi { throw 'select rejected' } -ParameterFilter { $Path -like '*$select=*' }
        Mock InvokeNxoApi {
            [PSCustomObject]@{ data = [PSCustomObject]@{ stats = @(
                        [PSCustomObject]@{ timestamp = 't1'; storageUsageBytes = 100 }
                        [PSCustomObject]@{ timestamp = 't2'; storageUsageBytes = 200 }
                    ) } }
        }
        $result = GetNxoStatSeries @param
        @($result['storageUsageBytes']).value | Should -Be @(100, 200)
        Should -Invoke InvokeNxoApi -Times 2 -Exactly
    }

    It 'Skips $select with -NoSelect and passes the preferred version' {
        Mock InvokeNxoApi { [PSCustomObject]@{ data = $null } }
        $null = GetNxoStatSeries @param -NoSelect -PreferVersion 'v4.3'
        Should -Invoke InvokeNxoApi -Times 1 -Exactly -ParameterFilter { $Path -notlike '*$select*' -and $PreferVersion -eq 'v4.3' }
    }
}
