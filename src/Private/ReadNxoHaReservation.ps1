function ReadNxoHaReservation {
    <#
    .SYNOPSIS
        Asks the engineer whether HA reservation is enabled on a cluster.

    .DESCRIPTION
        Internal helper for Test-NxoUpgradeReadiness. haMemoryReservedBytes only exists from
        API revision v4.3 on; on older revisions the engineer checks the setting in the UI and
        confirms it. Up to three attempts; returns Y, N or S (skip), or $null when nothing
        valid was entered or -NonInteractive is set.

    .PARAMETER ClusterName
        Cluster name, for the prompt.

    .PARAMETER UiPath
        Where to find the setting in the UI.

    .PARAMETER NonInteractive
        Do not prompt.

    .EXAMPLE
        ReadNxoHaReservation -ClusterName NTNX-CL01 -UiPath 'Prism Element > Settings > ...'

    .OUTPUTS
        System.String or $null

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([string])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
        Justification = 'Interactive console prompt: the instructions must be shown next to Read-Host, not in an output stream.')]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $ClusterName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $UiPath,

        [Parameter()]
        [switch]
        $NonInteractive
    )

    if ($NonInteractive) { return $null }

    Write-Host ''
    Write-Host "  HA reservation on $ClusterName cannot be read via the API." -ForegroundColor Yellow
    Write-Host "  Please check in the UI: $UiPath" -ForegroundColor Yellow
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $answer = ([string](Read-Host '  Is HA reservation enabled? [Y]es / [N]o / [S]kip')).Trim().ToUpperInvariant()
        if ($answer -and $answer.Substring(0, 1) -in @('Y', 'N', 'S')) {
            return $answer.Substring(0, 1)
        }
    }

    return $null
}
