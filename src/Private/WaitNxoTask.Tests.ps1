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

Describe 'WaitNxoTask' {
    BeforeEach {
        $connection = New-TestConnection
        Mock Start-Sleep {}
        Mock Write-Progress {}
    }

    It 'Returns as soon as the task succeeded' {
        $script:polls = 0
        Mock InvokeNxoApi {
            $script:polls++
            $status = if ($script:polls -lt 3) { 'RUNNING' } else { 'SUCCEEDED' }
            [PSCustomObject]@{ data = [PSCustomObject]@{ status = $status; progressPercentage = 50 } }
        }

        (WaitNxoTask -Connection $connection -TaskExtId 'task-1' -Activity 'x').status | Should -Be 'SUCCEEDED'
        Should -Invoke InvokeNxoApi -Times 3 -Exactly -ParameterFilter { $Namespace -eq 'prism' -and $Path -eq '/config/tasks/task-1' }
    }

    It 'Returns failed tasks' {
        Mock InvokeNxoApi { [PSCustomObject]@{ data = [PSCustomObject]@{ status = 'FAILED' } } }
        (WaitNxoTask -Connection $connection -TaskExtId 't').status | Should -Be 'FAILED'
    }

    It 'Returns the last state after the timeout' {
        Mock InvokeNxoApi { [PSCustomObject]@{ data = [PSCustomObject]@{ status = 'RUNNING'; progressPercentage = 10 } } }
        $script:clock = [datetime]'2026-01-01T00:00:00'
        Mock Get-Date { $script:clock = $script:clock.AddSeconds(30); $script:clock }

        (WaitNxoTask -Connection $connection -TaskExtId 't' -TimeoutSeconds 1).status | Should -Be 'RUNNING'
    }
}
