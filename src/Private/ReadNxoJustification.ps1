function ReadNxoJustification {
    <#
    .SYNOPSIS
        Asks the engineer for a justification of each warning.

    .DESCRIPTION
        Internal helper for Test-NxoUpgradeReadiness. Open findings must not cause a NO-GO on
        their own; instead the engineer explains why each warning does not affect the upgrade
        (e.g. irrelevant for the upgrade, false positive fixed in version X). The answer is
        stored in the Justification property of the check row. Up to three attempts per
        warning. Rows without answer (or with -NonInteractive) get "(no justification
        provided)".

    .PARAMETER Check
        The check rows of one cluster.

    .PARAMETER ClusterName
        Cluster name, for the prompt.

    .PARAMETER NonInteractive
        Do not prompt.

    .EXAMPLE
        ReadNxoJustification -Check $checks -ClusterName NTNX-CL01

    .OUTPUTS
        None (the rows are updated in place)

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive console prompt: each finding must be shown next to Read-Host, not in an output stream.')]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]
        $Check,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ClusterName,

        [Parameter()]
        [switch]
        $NonInteractive
    )

    $warnings = @($Check | Where-Object { $_.Result -eq 'WARN' })

    if ($warnings.Count -and -not $NonInteractive) {
        Write-Host ''
        Write-Host "$($warnings.Count) finding(s) on $ClusterName need a justification (why it does not affect the upgrade):" -ForegroundColor Yellow
        foreach ($warning in $warnings) {
            Write-Host ''
            Write-Host "  [$($warning.Value)] $($warning.Check)" -ForegroundColor Yellow
            Write-Host "  $($warning.Detail)" -ForegroundColor DarkGray
            $answer = ''
            for ($attempt = 0; $attempt -lt 3 -and -not $answer; $attempt++) {
                # [string] guards against $null when the input is redirected or closed
                $answer = ([string](Read-Host '  Justification')).Trim()
            }
            if ($answer) { $warning.Justification = $answer }
        }
    }

    foreach ($warning in $warnings) {
        if (-not $warning.Justification) { $warning.Justification = '(no justification provided)' }
    }
}
