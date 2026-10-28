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

Describe 'FormatNxoTotal' {
    It 'Sums known sizes as lower bound' {
        $items = @([PSCustomObject]@{ SizeBytes = 1GB }, [PSCustomObject]@{ SizeBytes = 512MB })
        FormatNxoTotal -Item $items | Should -Be 'at least 1.5 GiB'
    }

    It 'Mentions items without size' {
        $items = @([PSCustomObject]@{ SizeBytes = 1GB }, [PSCustomObject]@{ SizeBytes = $null }, [PSCustomObject]@{ SizeBytes = $null })
        FormatNxoTotal -Item $items | Should -Be 'at least 1.0 GiB (plus 2 recovery points without size)'
    }

    It 'Reports unknown when no size is known' {
        FormatNxoTotal -Item @([PSCustomObject]@{ SizeBytes = $null }) | Should -Be 'unknown (no size reported)'
        FormatNxoTotal -Item @() | Should -Be 'unknown (no size reported)'
    }
}
