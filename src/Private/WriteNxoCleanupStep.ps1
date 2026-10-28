function WriteNxoCleanupStep {
    <#
    .SYNOPSIS
        Shows the title of a cleanup step with the run mode.

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup. Prints
        "=== Step n of m: title [MODE] ===" with a coloured mode tag (LIVE, DRY RUN, STORAGE
        REPORT), so the mode is visible in every step, and logs the step. Without -Number only
        the mode tag is printed.

    .PARAMETER State
        Run state (hashtable with Mode, TotalSteps, LogFile).

    .PARAMETER Number
        Step number.

    .PARAMETER Title
        Step title.

    .EXAMPLE
        WriteNxoCleanupStep -State $state -Number 1 -Title 'Connect to Prism Central'

    .OUTPUTS
        None

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive console wizard: coloured step headers are part of the user interface.')]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]
        $State,

        [Parameter()]
        [ValidateRange(1, 10)]
        [int]
        $Number,

        [Parameter()]
        [string]
        $Title
    )

    if ($Number) {
        Write-Host ''
        Write-Host ('=== Step {0} of {1}: {2} ' -f $Number, $State.TotalSteps, $Title) -ForegroundColor Cyan -NoNewline
    }

    switch ($State.Mode) {
        'LIVE' { Write-Host ' LIVE ' -ForegroundColor White -BackgroundColor DarkRed -NoNewline }
        'DRY RUN' { Write-Host ' DRY RUN ' -ForegroundColor Black -BackgroundColor Yellow -NoNewline }
        default { Write-Host ' STORAGE REPORT ' -ForegroundColor Black -BackgroundColor Cyan -NoNewline }
    }

    if ($Number) {
        Write-Host ' ===' -ForegroundColor Cyan
        WriteNxoCleanupLog -State $State -Message ('Step {0}: {1}' -f $Number, $Title)
    }
}
