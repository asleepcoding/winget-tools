function ConvertTo-SafeFileName {
    <#
    .SYNOPSIS
        Sanitizes a string for use as a file name.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Name
    )

    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $sb = [System.Text.StringBuilder]::new($Name.Length)
    foreach ($c in $Name.ToCharArray()) {
        if ($c -in $invalid) {
            [void]$sb.Append('_')
        } else {
            [void]$sb.Append($c)
        }
    }
    return $sb.ToString()
}
