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

Describe 'GetNxoClusterEvent' {
    BeforeAll {
        $from = [datetime]::new(2026, 10, 28, 10, 0, 0, [System.DateTimeKind]::Utc).ToLocalTime()
        $to = $from.AddHours(1)
        $testEvents = @(
            [PSCustomObject]@{ creationTime = '2026-10-28T10:30:00Z'; eventType = 'A'; serviceName = 'ncc'; message = 'NCC {state}'; parameters = @([PSCustomObject]@{ paramName = 'state'; paramValue = 'done' }); clusterUUID = 'c1' }
            [PSCustomObject]@{ creationTime = '2026-10-28T10:10:00Z'; eventType = 'B'; message = 'other source'; sourceClusterUUID = 'c1' }
            [PSCustomObject]@{ creationTime = '2026-10-28T10:20:00Z'; eventType = 'C'; message = 'other cluster'; clusterUUID = 'c2' }
            [PSCustomObject]@{ creationTime = '2026-10-28T09:00:00Z'; eventType = 'D'; message = 'too old'; clusterUUID = 'c1' }
        )
    }
    BeforeEach {
        $connection = New-TestConnection
    }

    It 'Filters by cluster and window, sorted by time' {
        Mock GetNxoPagedList { $testEvents }
        $result = @(GetNxoClusterEvent -Connection $connection -ClusterExtId 'c1' -From $from -To $to)
        $result.Type | Should -Be @('B', 'A')
        $result[1].Message | Should -Be 'NCC done'
        Should -Invoke GetNxoPagedList -ParameterFilter { $Query -like '$filter=creationTime%20ge%20*' }
    }

    It 'Pages newest-first when the filter is rejected' {
        Mock GetNxoPagedList { throw 'filter rejected' }
        Mock InvokeNxoApi { [PSCustomObject]@{ data = $testEvents } }
        @(GetNxoClusterEvent -Connection $connection -ClusterExtId 'c1' -From $from -To $to).Count | Should -Be 2
        Should -Invoke InvokeNxoApi -Times 1 -Exactly -ParameterFilter { $Path -like '/serviceability/events?$orderby=creationTime%20desc&$page=0&$limit=100' }
    }
}
