function ConvertToNxoStorageRow {
    <#
    .SYNOPSIS
        Builds one row of the cleanup storage history.

    .DESCRIPTION
        Internal helper for Invoke-NxoRecoveryPointCleanup. Event Measured stores the storage
        of one cluster; event Deleted stores how many recovery points a live run deleted on a
        Prism Central and how much space it expected to free.

    .PARAMETER State
        Run state (Stamp, Mode).

    .PARAMETER EventName
        Measured or Deleted.

    .PARAMETER PrismCentral
        Prism Central address.

    .PARAMETER Measurement
        Cluster storage measurement (from GetNxoClusterStorage).

    .PARAMETER DeletedCount
        Number of deleted recovery points (event Deleted).

    .PARAMETER FreedAtLeastBytes
        Expected freed space (event Deleted).

    .EXAMPLE
        ConvertToNxoStorageRow -State $state -EventName Measured -PrismCentral pc01 -Measurement $m

    .OUTPUTS
        PSCustomObject

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]
        $State,

        [Parameter(Mandatory)]
        [ValidateSet('Measured', 'Deleted')]
        [string]
        $EventName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $PrismCentral,

        [Parameter()]
        [AllowNull()]
        [object]
        $Measurement,

        [Parameter()]
        [int]
        $DeletedCount,

        [Parameter()]
        [AllowNull()]
        [object]
        $FreedAtLeastBytes
    )

    [PSCustomObject][ordered]@{
        TimeUtc           = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
        RunId             = $State.Stamp
        Mode              = $State.Mode
        Event             = $EventName
        PrismCentral      = $PrismCentral
        Cluster           = $Measurement.Cluster
        ClusterExtId      = $Measurement.ClusterExtId
        UsedBytes         = $Measurement.UsedBytes
        LogicalUsedBytes  = $Measurement.LogicalUsedBytes
        CapacityBytes     = $Measurement.CapacityBytes
        DeletedCount      = if ($EventName -eq 'Deleted') { $DeletedCount } else { $null }
        FreedAtLeastBytes = $FreedAtLeastBytes
    }
}
