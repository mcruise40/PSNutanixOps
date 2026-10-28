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

Describe 'GetNxoVmStatSample' {
    BeforeEach {
        $connection = New-TestConnection
        $param = @{
            Connection = $connection; VmExtId = 'vm-1'; Field = @('hypervisorCpuReadyTimePpm')
            StartTime = [datetime]'2026-10-01T00:00:00Z'; EndTime = [datetime]'2026-10-02T00:00:00Z'
        }
    }

    It 'Selects the fields and returns the samples' {
        Mock InvokeNxoApi { [PSCustomObject]@{ data = [PSCustomObject]@{ stats = @([PSCustomObject]@{ hypervisorCpuReadyTimePpm = 1 }, $null, [PSCustomObject]@{ hypervisorCpuReadyTimePpm = 2 }) } } }
        $state = @{}
        @(GetNxoVmStatSample @param -State $state).Count | Should -Be 2
        $state.UseSelect | Should -BeTrue
        Should -Invoke InvokeNxoApi -ParameterFilter {
            $Namespace -eq 'vmm' -and $Path -like '/ahv/stats/vms/vm-1?*&$select=stats%2Ftimestamp%2Cstats%2FhypervisorCpuReadyTimePpm'
        }
    }

    It 'Falls back without $select and remembers it' {
        Mock InvokeNxoApi { throw 'rejected' } -ParameterFilter { $Path -like '*$select=*' }
        Mock InvokeNxoApi { [PSCustomObject]@{ data = [PSCustomObject]@{ stats = @([PSCustomObject]@{ x = 1 }) } } }
        $state = @{ UseSelect = $true }
        @(GetNxoVmStatSample @param -State $state).Count | Should -Be 1
        $state.UseSelect | Should -BeFalse

        $null = GetNxoVmStatSample @param -State $state
        Should -Invoke InvokeNxoApi -Times 2 -Exactly -ParameterFilter { $Path -notlike '*$select=*' }
    }
}
