function GetNxoPropertyValue {
    <#
    .SYNOPSIS
        Reads a property whose name is only known at run time.

    .DESCRIPTION
        Internal helper. Stats responses carry one property per metric, and the metric name is
        a variable. Reading it through PSObject.Properties avoids dynamic member access
        ($object.$name) and returns $null for missing properties or a $null object.

    .PARAMETER InputObject
        The object to read from.

    .PARAMETER Name
        Property name.

    .EXAMPLE
        GetNxoPropertyValue -InputObject $response.data -Name 'hypervisorCpuUsagePpm'

    .OUTPUTS
        System.Object

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]
        $InputObject,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Name
    )

    if ($null -eq $InputObject) { return $null }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }

    return $property.Value
}
