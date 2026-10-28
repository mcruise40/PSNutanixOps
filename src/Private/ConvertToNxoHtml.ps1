function ConvertToNxoHtml {
    <#
    .SYNOPSIS
        HTML-encodes a value for the HTML reports.

    .DESCRIPTION
        Internal helper. Converts the value to a string and encodes <, >, &, quotes and other
        special characters. $null becomes an empty string.

    .PARAMETER Text
        The value to encode.

    .EXAMPLE
        ConvertToNxoHtml -Text '<b>'
        Returns &lt;b&gt;

    .OUTPUTS
        System.String

    .NOTES
        Private function - not exported from module
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [object]
        $Text
    )

    if ($null -eq $Text) { return '' }

    return [System.Net.WebUtility]::HtmlEncode([string]$Text)
}
