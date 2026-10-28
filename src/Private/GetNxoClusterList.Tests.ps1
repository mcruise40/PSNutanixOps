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

Describe 'GetNxoClusterList' {
    BeforeEach {
        $connection = New-TestConnection
        Mock GetNxoPagedList {
            [PSCustomObject]@{ extId = 'c1'; name = 'NTNX-CL01'; config = [PSCustomObject]@{ clusterFunction = @('AOS') } }
            [PSCustomObject]@{ extId = 'c2'; name = 'NTNX-CL02'; config = $null }
            [PSCustomObject]@{ extId = 'pc'; name = 'PC'; config = [PSCustomObject]@{ clusterFunction = @('PRISM_CENTRAL') } }
        }
    }

    It 'Removes the Prism Central self-registration' {
        @(GetNxoClusterList -Connection $connection).name | Should -Be @('NTNX-CL01', 'NTNX-CL02')
        Should -Invoke GetNxoPagedList -ParameterFilter { $Namespace -eq 'clustermgmt' -and $Path -eq '/config/clusters' }
    }

    It 'Filters by cluster name case-insensitively' {
        @(GetNxoClusterList -Connection $connection -ClusterName 'ntnx-cl02', 'missing').name | Should -Be @('NTNX-CL02')
    }

    It 'Passes the preferred version' {
        $null = GetNxoClusterList -Connection $connection -PreferVersion 'v4.3'
        Should -Invoke GetNxoPagedList -ParameterFilter { $PreferVersion -eq 'v4.3' }
    }
}
