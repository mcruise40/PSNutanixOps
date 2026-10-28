function GetNxoItemCount {
    <#
    .SYNOPSIS
        Counts the real items of a value that may be $null, one object or an array.

    .DESCRIPTION
        Internal helper. @($null).Count is 1 in PowerShell, which makes counts of optional API
        properties (gpus, pcieDevices, gpuList, ...) wrong. $null entries and empty or
        whitespace-only strings are not counted.

    .PARAMETER Value
        The value to count.

    .EXAMPLE
        GetNxoItemCount -Value $vm.gpus

    .OUTPUTS
        System.Int32

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object]
        $Value
    )

    $items = @($Value | Where-Object {
            $null -ne $_ -and -not ($_ -is [string] -and [string]::IsNullOrWhiteSpace($_))
        })

    return $items.Count
}
