function AddNxoCheck {
    <#
    .SYNOPSIS
        Adds one check result to the result list of an upgrade readiness run.

    .DESCRIPTION
        Internal helper for Test-NxoUpgradeReadiness. Every check row has the same shape:
        Check, Result (PASS, WARN, FAIL, INFO, SKIPPED), Value, Threshold, Detail and an
        empty Justification that is filled for warnings later.

    .PARAMETER List
        The result list of the cluster.

    .PARAMETER Check
        Name of the check.

    .PARAMETER Result
        PASS, WARN, FAIL, INFO or SKIPPED.

    .PARAMETER Value
        Measured value.

    .PARAMETER Threshold
        Threshold or expectation.

    .PARAMETER Detail
        Explanation.

    .EXAMPLE
        AddNxoCheck -List $checks -Check 'Data resiliency' -Result PASS -Value 'FT 1' -Threshold 'FT >= 1' -Detail '...'

    .OUTPUTS
        None

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]
        $List,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Check,

        [Parameter(Mandatory)]
        [ValidateSet('PASS', 'WARN', 'FAIL', 'INFO', 'SKIPPED')]
        [string]
        $Result,

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $Value = '',

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $Threshold = '',

        [Parameter()]
        [AllowEmptyString()]
        [string]
        $Detail = ''
    )

    $List.Add([PSCustomObject][ordered]@{
            Check         = $Check
            Result        = $Result
            Value         = $Value
            Threshold     = $Threshold
            Detail        = $Detail
            Justification = $null
        })
}
