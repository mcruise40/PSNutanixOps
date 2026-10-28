function GetNxoVmStatSample {
    <#
    .SYNOPSIS
        Reads the stats samples of one AHV VM.

    .DESCRIPTION
        Internal helper for GET /vmm/<revision>/ahv/stats/vms/{extId}. The first request
        uses $select to keep the response small. If Prism Central rejects the $select
        expression, the request is repeated without it and State.UseSelect is set to $false,
        so the following calls of the same run skip $select right away.

    .PARAMETER Connection
        Connection object from the connection store.

    .PARAMETER VmExtId
        External ID of the VM.

    .PARAMETER Field
        Stats fields to select, e.g. hypervisorCpuReadyTimePpm.

    .PARAMETER StartTime
        Start of the window.

    .PARAMETER EndTime
        End of the window.

    .PARAMETER SamplingInterval
        Seconds per data point.

    .PARAMETER StatType
        Down-sampling operator: AVG, MAX, MIN or LAST.

    .PARAMETER State
        Hashtable shared by the calls of one run; key UseSelect (default $true).

    .EXAMPLE
        GetNxoVmStatSample -Connection $c -VmExtId $vm.extId -Field hypervisorCpuReadyTimePpm -StartTime $s -EndTime $e -State $state

    .OUTPUTS
        PSCustomObject (vmm.v4.ahv.stats.VmStatsTuple)

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [PSCustomObject]
        $Connection,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $VmExtId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string[]]
        $Field,

        [Parameter(Mandatory)]
        [datetime]
        $StartTime,

        [Parameter(Mandatory)]
        [datetime]
        $EndTime,

        [Parameter()]
        [ValidateRange(30, 86400)]
        [int]
        $SamplingInterval = 300,

        [Parameter()]
        [ValidateSet('AVG', 'MAX', 'MIN', 'LAST')]
        [string]
        $StatType = 'AVG',

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]
        $State
    )

    $query = '$startTime={0}&$endTime={1}&$samplingInterval={2}&$statType={3}' -f
    [uri]::EscapeDataString((ConvertToNxoIsoTime -Date $StartTime)),
    [uri]::EscapeDataString((ConvertToNxoIsoTime -Date $EndTime)),
    $SamplingInterval, $StatType
    $path = '/ahv/stats/vms/{0}?{1}' -f $VmExtId, $query

    if (-not $State.ContainsKey('UseSelect')) { $State.UseSelect = $true }

    $response = $null
    if ($State.UseSelect) {
        $select = [uri]::EscapeDataString((@('stats/timestamp') + @($Field | ForEach-Object { "stats/$_" })) -join ',')
        try {
            $response = InvokeNxoApi -Connection $Connection -Namespace vmm -Path ('{0}&$select={1}' -f $path, $select)
        } catch {
            Write-Verbose "$($MyInvocation.MyCommand): `$select rejected, retrying without it: $_"
            $State.UseSelect = $false
        }
    }
    if ($null -eq $response) {
        $response = InvokeNxoApi -Connection $Connection -Namespace vmm -Path $path
    }

    foreach ($sample in @($response.data.stats | Where-Object { $null -ne $_ })) {
        $sample
    }
}
