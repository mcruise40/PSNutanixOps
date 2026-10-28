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

Describe 'StartNxoNccCheck' {
    BeforeEach {
        $connection = New-TestConnection
        Mock Start-Sleep {}
        Mock Write-Host {}
        Mock Write-Warning {}
        $param = @{ Connection = $connection; ClusterExtId = 'c1'; ClusterName = 'CL01' }
    }

    It 'Starts NCC with the given recipients' {
        Mock InvokeNxoApi { [PSCustomObject]@{ data = [PSCustomObject]@{ extId = 'ncc-1' } } }
        $result = StartNxoNccCheck @param -State @{ Recipients = @('ops@example.com'); Asked = $false }
        $result.TaskId | Should -Be 'ncc-1'
        $result.Error | Should -BeNullOrEmpty
        Should -Invoke InvokeNxoApi -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Path -eq '/serviceability/clusters/c1/$actions/run-system-defined-checks' -and
            $Body.additionalRecipients -contains 'ops@example.com' -and $Body.shouldSendReportToConfiguredRecipients -eq $false
        }
    }

    It 'Uses the configured recipients and checks the task' {
        Mock InvokeNxoApi { [PSCustomObject]@{ data = [PSCustomObject]@{ extId = 'ncc-1' } } } -ParameterFilter { $Method -eq 'POST' }
        Mock InvokeNxoApi { [PSCustomObject]@{ data = [PSCustomObject]@{ status = 'RUNNING' } } }
        (StartNxoNccCheck @param -State @{ Recipients = @(); Asked = $false }).TaskId | Should -Be 'ncc-1'
        Should -Invoke InvokeNxoApi -ParameterFilter { $Path -eq '/config/tasks/ncc-1' }
    }

    It 'Asks once for a recipient when no alert email is configured' {
        $script:posts = 0
        Mock InvokeNxoApi {
            $script:posts++
            if ($script:posts -eq 1) { throw 'NCC-40031 no email configured' }
            [PSCustomObject]@{ data = [PSCustomObject]@{ extId = 'ncc-2' } }
        } -ParameterFilter { $Method -eq 'POST' }
        Mock Read-Host { 'ops@example.com; noc@example.com' }
        $state = @{ Recipients = @(); Asked = $false }

        (StartNxoNccCheck @param -State $state).TaskId | Should -Be 'ncc-2'
        $state.Recipients | Should -Be @('ops@example.com', 'noc@example.com')
        $state.Asked | Should -BeTrue
        Should -Invoke Read-Host -Times 1 -Exactly
    }

    It 'Detects the asynchronous email failure and gives up without answer' {
        Mock InvokeNxoApi { [PSCustomObject]@{ data = [PSCustomObject]@{ extId = 'ncc-3' } } } -ParameterFilter { $Method -eq 'POST' }
        Mock InvokeNxoApi { [PSCustomObject]@{ data = [PSCustomObject]@{ status = 'FAILED'; errorMessages = @([PSCustomObject]@{ message = 'no email configured' }) } } }
        Mock Read-Host { '' }

        $result = StartNxoNccCheck @param -State @{ Recipients = @(); Asked = $false }
        $result.TaskId | Should -BeNullOrEmpty
        $result.Error | Should -BeLike 'No recipient*'
    }

    It 'Does not prompt with -NonInteractive' {
        Mock InvokeNxoApi { throw 'no email configured' }
        Mock Read-Host { 'x' }
        (StartNxoNccCheck @param -State @{ Recipients = @(); Asked = $false } -NonInteractive).Error | Should -BeLike 'No recipient*'
        Should -Invoke Read-Host -Times 0 -Exactly
    }

    It 'Reports other errors' {
        Mock InvokeNxoApi { throw 'HTTP 500 internal' }
        $result = StartNxoNccCheck @param -State @{ Recipients = @('a@b.c'); Asked = $false }
        $result.Error | Should -BeLike '*internal*'
        Should -Invoke Write-Warning -Times 1 -Exactly
    }
}
