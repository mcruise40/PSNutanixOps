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

Describe 'Invoke-NxoRecoveryPointCleanup with a simulated Prism Central' {
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
    Describe 'Invoke-NxoRecoveryPointCleanup' {
        BeforeEach {
            Mock Write-Host {}
            $logFolder = Join-Path -Path $TestDrive -ChildPath ([guid]::NewGuid())
            $script:answers = [System.Collections.Generic.Queue[string]]::new()
            Mock Read-Host { if ($script:answers.Count) { $script:answers.Dequeue() } else { 'q' } }
            function Set-TestAnswer { param([string[]]$Answer) foreach ($item in $Answer) { $script:answers.Enqueue($item) } }
        }

        It 'Lists the candidates in a dry run without deleting' {
            Set-TestAnswer 'd 1', 'list', 'help', 'nonsense', 'all', 'y'
            Invoke-NxoRecoveryPointCleanup -WhatIf -LogDirectory $logFolder -ExportCsv (Join-Path -Path $logFolder -ChildPath 'list.csv')

            $script:FakeNxoData.Rps.Count | Should -Be 3
            $results = @(Import-Csv -LiteralPath (Get-ChildItem -Path $logFolder -Filter '*_DRYRUN_results.csv').FullName -UseCulture)
            $results.Status | Should -Be @('Not deleted (dry run)', 'Not deleted (dry run)')
            @(Import-Csv -LiteralPath (Join-Path -Path $logFolder -ChildPath 'list.csv') -UseCulture).RecoveryPointExtId | Should -Be @('rp-2', 'rp-1')
            Should -Invoke Write-Host -ParameterFilter { $Object -like 'Row 1: OLD-VM (VM missing)' }
        }

        It 'Deletes the expired recovery points after confirmation' {
            Set-TestAnswer 'expired', '', 'expired', '1'
            Invoke-NxoRecoveryPointCleanup -LogDirectory $logFolder -Confirm:$false

            $script:FakeNxoData.Rps.extId | Should -Be @('rp-2', 'rp-3')
            $results = @(Import-Csv -LiteralPath (Get-ChildItem -Path $logFolder -Filter '*_LIVE_results.csv').FullName -UseCulture)
            $results.Status | Should -Be @('Deleted')
            $history = @(Import-Csv -LiteralPath (Join-Path -Path $logFolder -ChildPath 'RecoveryPointCleanup_storage-history.csv') -UseCulture)
            $history.Event | Should -Contain 'Deleted'
            Should -Invoke Write-Host -ParameterFilter { $Object -eq 'Not confirmed. Back to the selection.' }
        }

        It 'Selects missing VMs by the age of their newest recovery point' {
            Set-TestAnswer 'missing 90', 'missing 30', '1'
            Invoke-NxoRecoveryPointCleanup -LogDirectory $logFolder -Confirm:$false
            $script:FakeNxoData.Rps.extId | Should -Be @('rp-1', 'rp-3')
            Should -Invoke Write-Host -ParameterFilter { $Object -eq 'No rows match.' }
        }

        It 'Quits without deleting' {
            Set-TestAnswer 'q'
            Invoke-NxoRecoveryPointCleanup -LogDirectory $logFolder
            $script:FakeNxoData.Rps.Count | Should -Be 3
            Should -Invoke Write-Host -ParameterFilter { $Object -eq 'Cancelled. Nothing was deleted.' }
        }

        It 'Reports the storage only with -StorageReport' {
            Invoke-NxoRecoveryPointCleanup -StorageReport -LogDirectory $logFolder
            Test-Path -LiteralPath (Join-Path -Path $logFolder -ChildPath 'RecoveryPointCleanup_storage-history.csv') | Should -BeTrue
            Should -Invoke Read-Host -Times 0 -Exactly
            Should -Invoke InvokeNxoRestMethod -Times 0 -Exactly -ParameterFilter { $Path -like '/dataprotection/*/config/recovery-points?$page*' }
        }

        It 'Says when there is nothing to clean up' {
            $script:FakeNxoData.Rps.Clear()
            Invoke-NxoRecoveryPointCleanup -LogDirectory $logFolder
            Should -Invoke Write-Host -ParameterFilter { $Object -like 'Nothing to clean up*' }
        }

        It 'Marks a deleted VM whose name is used again as replaced' {
            $script:FakeNxoData.Vms[0].name = 'OLD-VM'
            Set-TestAnswer 'd 1', 'q'
            Invoke-NxoRecoveryPointCleanup -LogDirectory $logFolder
            Should -Invoke Write-Host -ParameterFilter { $Object -eq 'Row 1: OLD-VM (VM replaced)' }
        }

        It 'Records deletions that were already gone or failed' {
            Mock InvokeNxoApi { New-FakeNxoHttpError -StatusCode 404 } -ParameterFilter { $Method -eq 'DELETE' -and $Path -like '*/rp-2' }
            Mock InvokeNxoApi { [PSCustomObject]@{ data = [PSCustomObject]@{ extId = 'task-bad' } } } -ParameterFilter { $Method -eq 'DELETE' -and $Path -like '*/rp-1' }
            Mock InvokeNxoApi { [PSCustomObject]@{ data = [PSCustomObject]@{ status = 'FAILED'; errorMessages = @([PSCustomObject]@{ message = 'rate limit reached' }) } } } -ParameterFilter { $Path -eq '/config/tasks/task-bad' }
            Set-TestAnswer 'all', '2'
            Invoke-NxoRecoveryPointCleanup -LogDirectory $logFolder -Confirm:$false -BatchSize 2
            $results = @(Import-Csv -LiteralPath (Get-ChildItem -Path $logFolder -Filter '*_LIVE_results.csv').FullName -UseCulture)
            ($results | Where-Object RecoveryPointExtId -EQ 'rp-2').Status | Should -Be 'Already gone'
            ($results | Where-Object RecoveryPointExtId -EQ 'rp-1').Status | Should -Be 'Failed'
            Should -Invoke Write-Host -ParameterFilter { $Object -like '*-BatchSize 2*' }
        }

        It 'Connects interactively when nothing is connected' {
            (GetNxoConnectionStore).Clear()
            Mock Get-Credential { $testCredential }
            Mock Connect-NxoPrismCentral { (GetNxoConnectionStore)[$Server[0]] = New-TestConnection }
            Set-TestAnswer '1', 'pc01.example.local', 'q'
            Invoke-NxoRecoveryPointCleanup -LogDirectory $logFolder
            Should -Invoke Connect-NxoPrismCentral -Times 1 -Exactly -ParameterFilter { $Server -eq 'pc01.example.local' }
            Should -Invoke Get-Credential -Times 1 -Exactly
        }

        It 'Offers to retry a failed login' {
            Mock TestNxoCleanupAccess { 'login works, but this user may not read VMs or recovery points' }
            Set-TestAnswer 'Q'
            Invoke-NxoRecoveryPointCleanup -LogDirectory $logFolder
            Should -Invoke Write-Host -ParameterFilter { $Object -like '  `[FAILED`] PC1*' }
            Should -Invoke Write-Host -ParameterFilter { $Object -eq 'Cancelled. Nothing was deleted.' }
        }
    }
}
