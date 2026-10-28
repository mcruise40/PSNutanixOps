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

Describe 'ShowNxoCleanupRowDetail' {
    BeforeEach {
        $testPc = [PSCustomObject]@{ Label = 'PC1'; Address = 'pc01' }
        $testItem = [PSCustomObject]@{
            Reason = 'Expired'; Type = 'VM'; Name = 'SQL01'; VmIds = @('vm-1'); VgIds = @(); Pc = $testPc; RpExtId = 'rp-1'; RpName = 'Daily'
            LocationAgnosticId = 'loc-1'; CreatedUtc = [datetime]::UtcNow.AddDays(-40); ExpiresUtc = [datetime]::UtcNow.AddDays(-5); SizeBytes = 1GB
        }
        $testRow = [PSCustomObject]@{
            Row = 1; Reason = 'Expired'; Name = ('A' * 50); Pcs = 'PC1'; Count = 1; OldestUtc = $testItem.CreatedUtc; NewestUtc = $testItem.CreatedUtc
            EntityNewestUtc = [datetime]::UtcNow; OverdueDays = 5; SizeBytes = 1GB; UnknownSize = 0; Items = @($testItem)
        }
        Mock Write-Host {}
    }

    It 'Shows the IDs, the newer recovery point and the items' {
        ShowNxoCleanupRowDetail -Row $testRow
        Should -Invoke Write-Host -ParameterFilter { $Object -eq 'IDs: vm-1' }
        Should -Invoke Write-Host -ParameterFilter { $Object -like 'Newest recovery point of this VM*' }
        Should -Invoke Write-Host -ParameterFilter { $Object -match 'rp-1' -and $Object -match 'Daily' }
    }
}
