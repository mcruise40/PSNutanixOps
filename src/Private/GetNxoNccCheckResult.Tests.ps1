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

Describe 'GetNxoNccCheckResult' {
    BeforeAll {
        $cluster = [PSCustomObject]@{ extId = 'c1'; name = 'CL01' }
        function New-TestTask {
            param([string]$Status, [object[]]$Details)
            [PSCustomObject]@{ status = $Status; completedTime = [datetime]::UtcNow; completionDetails = $Details; errorMessages = @(); warnings = @(); subSteps = @([PSCustomObject]@{ name = 'Run checks' }) }
        }
    }
    BeforeEach {
        $connection = New-TestConnection
        Mock GetNxoClusterEvent { [PSCustomObject]@{ Time = Get-Date; Type = 'X'; Message = 'm' } }
        Mock ResolveNxoNccCheck { [PSCustomObject]@{ Title = "Check $CheckId"; Kb = '' } }
        $task = @{ TaskId = 'ncc-1'; Started = (Get-Date).AddMinutes(-5); Error = $null }
    }

    It 'Returns WARN when NCC could not be started' {
        $result = GetNxoNccCheckResult -Connection $connection -Cluster $cluster -NccTask @{ TaskId = $null; Started = Get-Date; Error = 'no recipient' } -CheckCache @{}
        $result.Result | Should -Be 'WARN'
        $result.Value | Should -Be 'Not started'
        $result.Ncc | Should -BeNullOrEmpty
    }

    It 'Returns PASS when all checks passed' {
        Mock WaitNxoTask { New-TestTask -Status SUCCEEDED -Details @([PSCustomObject]@{ name = 'total'; value = '5' }, [PSCustomObject]@{ name = 'pass'; value = '5' }, [PSCustomObject]@{ name = 'status'; value = 'PASS' }) }
        $result = GetNxoNccCheckResult -Connection $connection -Cluster $cluster -NccTask $task -CheckCache @{} -Recipient 'ops@example.com'
        $result.Result | Should -Be 'PASS'
        $result.Value | Should -Be '5/5 PASS'
        $result.Ncc.Recipients | Should -Be 'ops@example.com'
        $result.Ncc.Overall | Should -Be 'PASS'
        @($result.Ncc.Events).Count | Should -Be 1
        $result.Ncc.Details | Should -Contain 'Step: Run checks'
    }

    It 'Returns WARN with the failed checks sorted by severity' {
        $summary = [PSCustomObject]@{ map = [PSCustomObject]@{ warnSdaExtIds = '3'; failSdaExtIds = '1,2' } }
        Mock WaitNxoTask { New-TestTask -Status SUCCEEDED -Details @([PSCustomObject]@{ name = 'total'; value = '10' }, [PSCustomObject]@{ name = 'pass'; value = '7' }, [PSCustomObject]@{ name = 'fail'; value = '2' }, [PSCustomObject]@{ name = 'warn'; value = '1' }, [PSCustomObject]@{ name = 'detailedSummary'; value = @($summary) }) }
        $result = GetNxoNccCheckResult -Connection $connection -Cluster $cluster -NccTask $task -CheckCache @{}
        $result.Result | Should -Be 'WARN'
        @($result.Ncc.Checks).Category | Should -Be @('FAIL', 'FAIL', 'WARN')
        $result.Detail | Should -BeLike '*FAIL 1 Check 1*'
    }

    It 'Returns PASS without summary when the task has no counters' {
        Mock WaitNxoTask { New-TestTask -Status SUCCEEDED -Details @() }
        (GetNxoNccCheckResult -Connection $connection -Cluster $cluster -NccTask $task -CheckCache @{}).Value | Should -Be 'Completed'
    }

    It 'Returns WARN for failed and unfinished runs' {
        Mock WaitNxoTask { $t = New-TestTask -Status FAILED -Details @(); $t.errorMessages = @([PSCustomObject]@{ message = 'no email configured' }); $t }
        $result = GetNxoNccCheckResult -Connection $connection -Cluster $cluster -NccTask $task -CheckCache @{}
        $result.Value | Should -Be 'Failed'
        $result.Detail | Should -BeLike '*-NccReportRecipient*'

        Mock WaitNxoTask { $t = New-TestTask -Status RUNNING -Details @(); $t.completedTime = $null; $t }
        $result = GetNxoNccCheckResult -Connection $connection -Cluster $cluster -NccTask $task -CheckCache @{} -TimeoutMinutes 30
        $result.Value | Should -Be 'RUNNING'
        $result.Detail | Should -BeLike '*30 min*'
    }
}
