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

Describe 'GetNxoNameMap' {
    BeforeEach {
        $connection = New-TestConnection
    }

    It 'Builds the <Kind> map' -TestCases @(
        @{ Kind = 'Cluster'; Namespace = 'clustermgmt'; Item = [PSCustomObject]@{ extId = 'x'; name = 'NTNX-CL01' }; Expected = 'NTNX-CL01' }
        @{ Kind = 'Host'; Namespace = 'clustermgmt'; Item = [PSCustomObject]@{ extId = 'x'; hostName = 'ntnx-h1' }; Expected = 'ntnx-h1' }
        @{ Kind = 'Category'; Namespace = 'prism'; Item = [PSCustomObject]@{ extId = 'x'; key = 'Env'; value = 'Prod' }; Expected = 'Env:Prod' }
        @{ Kind = 'Subnet'; Namespace = 'networking'; Item = [PSCustomObject]@{ extId = 'x'; name = 'VLAN100' }; Expected = 'VLAN100' }
    ) {
        Mock GetNxoPagedList { $Item; [PSCustomObject]@{ name = 'no id' } }
        $map = GetNxoNameMap -Connection $connection -Kind $Kind
        $map.Count | Should -Be 1
        $map['x'] | Should -Be $Expected
        Should -Invoke GetNxoPagedList -ParameterFilter { $Namespace -eq $Namespace }
    }

    It 'Returns an empty map and warns when the list fails' {
        Mock GetNxoPagedList { throw 'boom' }
        Mock Write-Warning {}
        (GetNxoNameMap -Connection $connection -Kind Subnet).Count | Should -Be 0
        Should -Invoke Write-Warning -Times 1 -Exactly
    }
}
