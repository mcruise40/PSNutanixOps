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

Describe 'NewNxoCpuSummaryRow' {
    BeforeAll {
        $series = @(
            [PSCustomObject]@{ timestamp = '2026-10-28T10:00:00Z'; value = 300000 }
            [PSCustomObject]@{ timestamp = '2026-10-28T11:00:00Z'; value = 600000 }
        )
        $base = @{ PrismCentral = 'pc01'; Cluster = 'CL01'; Name = 'CL01'; ThresholdPercent = 80 }
    }

    It 'Projects the cluster peak onto N-1 hosts' {
        $row = NewNxoCpuSummaryRow @base -Scope Cluster -Nodes 4 -Sample $series
        $row.MaxCpuPct | Should -Be 60
        $row.ProjectedN1Pct | Should -Be 80
        $row.AvgCpuPct | Should -Be 45
        $row.Status | Should -Be 'OK'
        $row.Samples | Should -Be 2
        $row.MaxCpuAt | Should -Be ([datetime]::new(2026, 10, 28, 11, 0, 0, [System.DateTimeKind]::Utc).ToLocalTime())
        $row.PSObject.TypeNames[0] | Should -Be 'PSNutanixOps.ClusterCpuPeak'
    }

    It 'Warns above the threshold' {
        (NewNxoCpuSummaryRow @base -Scope Cluster -Nodes 3 -Sample $series).Status | Should -Be 'WARN'
    }

    It 'Marks single-node clusters' {
        $row = NewNxoCpuSummaryRow @base -Scope Cluster -Nodes 1 -Sample $series
        $row.Status | Should -Be 'SINGLE NODE'
        $row.ProjectedN1Pct | Should -BeNullOrEmpty
    }

    It 'Has no projection on host rows' {
        $row = NewNxoCpuSummaryRow @base -Scope Host -Nodes 4 -Sample $series
        $row.Status | Should -Be 'OK'
        $row.ProjectedN1Pct | Should -BeNullOrEmpty
    }

    It 'Reports NO DATA without samples' {
        $row = NewNxoCpuSummaryRow @base -Scope Cluster -Nodes 4 -Sample @()
        $row.Status | Should -Be 'NO DATA'
        $row.Samples | Should -Be 0
    }
}
