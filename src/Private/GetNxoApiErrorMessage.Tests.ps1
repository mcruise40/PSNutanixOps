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

Describe 'GetNxoApiErrorMessage' {
    BeforeAll {
        function New-TestErrorRecord {
            param([string]$Body, [string]$Message = 'Response status code does not indicate success: 400')
            $record = [System.Management.Automation.ErrorRecord]::new([System.Exception]::new($Message), 'id', 'InvalidOperation', $null)
            if ($Body) { $record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new($Body) }
            $record
        }
    }

    It 'Extracts code and message of a Nutanix error body' {
        $body = '{"data":{"error":[{"code":"VMM-30100","message":"VM not found"},{"message":"second"}]}}'
        GetNxoApiErrorMessage -ErrorRecord (New-TestErrorRecord -Body $body) | Should -Be '[VMM-30100] VM not found second'
    }

    It 'Uses a non-JSON body as is' {
        GetNxoApiErrorMessage -ErrorRecord (New-TestErrorRecord -Body 'Bad gateway') | Should -Be 'Bad gateway'
    }

    It 'Falls back to the exception message' {
        GetNxoApiErrorMessage -ErrorRecord (New-TestErrorRecord -Message "line1`n  line2") | Should -Be 'line1 line2'
    }

    It 'Cuts long messages' {
        $result = GetNxoApiErrorMessage -ErrorRecord (New-TestErrorRecord -Message ('x' * 500))
        $result.Length | Should -Be 403
        $result | Should -BeLike '*...'
    }
}
