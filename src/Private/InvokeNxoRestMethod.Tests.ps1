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

Describe 'InvokeNxoRestMethod' {
    BeforeEach {
        $connection = New-TestConnection
        Mock Start-Sleep {}
    }

    It 'Builds the request for a GET call' {
        Mock Invoke-RestMethod { [PSCustomObject]@{ data = 'ok' } }

        $result = InvokeNxoRestMethod -Connection $connection -Path '/vmm/v4.2/ahv/config/vms?$limit=1'

        $result.data | Should -Be 'ok'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://pc01.example.local:9440/api/vmm/v4.2/ahv/config/vms?$limit=1' -and
            $Method -eq 'GET' -and $Authentication -eq 'Basic' -and $SkipCertificateCheck -and $null -eq $Headers
        }
    }

    It 'Adds the idempotency header and JSON body on writes' {
        Mock Invoke-RestMethod { [PSCustomObject]@{ data = 'ok' } }

        $null = InvokeNxoRestMethod -Connection $connection -Method POST -Path '/x' -Body @{ name = 'rp' }

        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Headers['NTNX-Request-Id'] -match '^[0-9a-f-]{36}$' -and $ContentType -eq 'application/json' -and ($Body | ConvertFrom-Json).name -eq 'rp'
        }
    }

    It 'Does not skip the certificate check unless the connection says so' {
        $connection.SkipCertificateCheck = $false
        Mock Invoke-RestMethod { 'ok' }
        $null = InvokeNxoRestMethod -Connection $connection -Path '/x'
        Should -Invoke Invoke-RestMethod -ParameterFilter { -not $SkipCertificateCheck }
    }

    It 'Retries after a rate-limit answer' {
        $script:calls = 0
        Mock Invoke-RestMethod {
            $script:calls++
            if ($script:calls -lt 3) { throw (New-TestHttpError -StatusCode 429) }
            'ok'
        }
        Mock Write-Warning {}

        InvokeNxoRestMethod -Connection $connection -Path '/x' | Should -Be 'ok'
        Should -Invoke Invoke-RestMethod -Times 3 -Exactly
        Should -Invoke Start-Sleep -Times 2 -Exactly
    }

    It 'Gives up after MaxRetry rate-limit answers' {
        Mock Invoke-RestMethod { throw (New-TestHttpError -StatusCode 429) }
        Mock Write-Warning {}

        { InvokeNxoRestMethod -Connection $connection -Path '/x' -MaxRetry 1 } | Should -Throw
        Should -Invoke Invoke-RestMethod -Times 2 -Exactly
    }

    It 'Throws with the status code and the request in the message' {
        Mock Invoke-RestMethod { throw (New-TestHttpError -StatusCode 404 -Message 'not found') }

        $failure = { InvokeNxoRestMethod -Connection $connection -Path '/vmm/v4.2/ahv/config/vms/x' } | Should -Throw -PassThru
        $failure.Exception.Data['StatusCode'] | Should -Be 404
        $failure.Exception.Message | Should -BeLike '*GET /vmm/v4.2/ahv/config/vms/x on pc01.example.local*'
    }

    It 'Validates the path' {
        { InvokeNxoRestMethod -Connection $connection -Path 'no-slash' } | Should -Throw
    }
}
