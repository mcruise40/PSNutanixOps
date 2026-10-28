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

Describe 'GetNxoPagedList' {
    BeforeEach {
        $connection = New-TestConnection
        Mock Write-Progress {}
    }

    It 'Reads pages until a page is not full' {
        Mock InvokeNxoApi {
            $page = [int]([regex]::Match($Path, '\$page=(\d+)').Groups[1].Value)
            $count = if ($page -lt 2) { 2 } else { 1 }
            [PSCustomObject]@{ data = @(1..$count | ForEach-Object { "p$page-$_" }) }
        }

        $items = @(GetNxoPagedList -Connection $connection -Namespace vmm -Path '/ahv/config/vms' -PageSize 2)

        $items.Count | Should -Be 5
        Should -Invoke InvokeNxoApi -Times 3 -Exactly
        Should -Invoke InvokeNxoApi -ParameterFilter { $Path -eq '/ahv/config/vms?$page=0&$limit=2' }
    }

    It 'Stops at totalAvailableResults' {
        Mock InvokeNxoApi { [PSCustomObject]@{ data = @('a', 'b'); metadata = [PSCustomObject]@{ totalAvailableResults = 2 } } }

        @(GetNxoPagedList -Connection $connection -Namespace vmm -Path '/x' -PageSize 2).Count | Should -Be 2
        Should -Invoke InvokeNxoApi -Times 1 -Exactly
    }

    It 'Appends an extra query and passes the preferred version' {
        Mock InvokeNxoApi { [PSCustomObject]@{ data = @() } }

        $null = GetNxoPagedList -Connection $connection -Namespace monitoring -Path '/alerts' -Query '$filter=x' -PreferVersion 'v4.3' -Activity 'reading'

        Should -Invoke InvokeNxoApi -ParameterFilter { $Path -eq '/alerts?$filter=x&$page=0&$limit=100' -and $PreferVersion -eq 'v4.3' }
        Should -Invoke Write-Progress -ParameterFilter { $Completed }
    }

    It 'Ignores $null entries and returns nothing for empty lists' {
        Mock InvokeNxoApi { [PSCustomObject]@{ data = $null } }
        @(GetNxoPagedList -Connection $connection -Namespace vmm -Path '/x').Count | Should -Be 0
    }

    It 'Rejects a path with query' {
        { GetNxoPagedList -Connection $connection -Namespace vmm -Path '/x?$limit=1' } | Should -Throw
    }
}
