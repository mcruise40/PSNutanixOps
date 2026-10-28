function ExpandNxoAlertText {
    <#
    .SYNOPSIS
        Fills the {placeholders} of an alert or event text.

    .DESCRIPTION
        Internal helper. Alert and event titles and messages contain placeholders such as
        {vm_name}. The values are in the parameters list: paramName plus paramValue, which is a
        typed object (monitoring.v4.common.StringValue, IntValue, BoolValue, DoubleValue) or a
        plain value.

    .PARAMETER Text
        Title or message with placeholders.

    .PARAMETER Parameters
        The parameters array of the alert or event.

    .EXAMPLE
        ExpandNxoAlertText -Text 'VM {vm_name} is down' -Parameters $alert.parameters

    .OUTPUTS
        System.String

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]
        $Text,

        [Parameter()]
        [AllowNull()]
        [object[]]
        $Parameters
    )

    if (-not $Text) { return $Text }

    foreach ($parameter in @($Parameters | Where-Object { $null -ne $_ -and $_.paramName })) {
        $raw = $parameter.paramValue
        $value = ''
        if ($null -ne $raw) {
            if ($raw -is [string] -or $raw -is [ValueType]) {
                $value = [string]$raw
            } else {
                foreach ($key in @('stringValue', 'intValue', 'doubleValue', 'boolValue', 'value')) {
                    $property = $raw.PSObject.Properties[$key]
                    if ($property) {
                        $value = [string]$property.Value
                        break
                    }
                }
            }
        }
        $Text = $Text.Replace('{' + $parameter.paramName + '}', $value)
    }

    return $Text
}
