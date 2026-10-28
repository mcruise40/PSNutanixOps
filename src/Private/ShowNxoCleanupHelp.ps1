function ShowNxoCleanupHelp {
    <#
    .SYNOPSIS
        Shows the selection commands of the cleanup wizard.

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup (step 4 and command "help").

    .EXAMPLE
        ShowNxoCleanupHelp

    .OUTPUTS
        None

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([void])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive console wizard: the command help is part of the console output.')]
    param ()

    Write-Host 'Which rows do you want to delete?'
    Write-Host '  1,4,7-12     rows by number'
    Write-Host '  all          every row in the list above (also not yet expired ones of deleted VMs)'
    Write-Host '  expired      all rows with reason Expired'
    Write-Host '  missing      all rows with reason VM missing or VG missing'
    Write-Host '  missing 30   the same, but only if the VM / volume group has no recovery point newer than 30 days'
    Write-Host '  d 5          show the recovery points of row 5'
    Write-Host '  list         show the table again'
    Write-Host '  csv          export the list to a CSV file'
    Write-Host '  q            quit without deleting'
    Write-Host 'Recommended: "expired" first, then "missing 30". Check "VM replaced" rows and recently'
    Write-Host 'deleted VMs with "d <row>" and select them by number only if nobody needs them back.'
}
