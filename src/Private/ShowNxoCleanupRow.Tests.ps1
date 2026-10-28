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

Describe 'ShowNxoCleanupRow' {
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

    It 'Renders the table to the host' {
        $second = $testRow.PSObject.Copy()
        $second.UnknownSize = 1
        $second.Count = 2
        $third = $testRow.PSObject.Copy()
        $third.UnknownSize = 1
        $third.Count = 1
        ShowNxoCleanupRow -Row @($testRow, $second, $third)
        Should -Invoke Write-Host -Times 1 -Exactly -ParameterFilter {
            $Object -match 'Reason' -and $Object -match ('A' * 42 + '\.\.\.') -and $Object -match '5 d' -and $Object -match '1\.0 GiB\*' -and $Object -match 'n/a'
        }
    }
}
