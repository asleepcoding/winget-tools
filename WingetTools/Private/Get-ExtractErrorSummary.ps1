function Get-ExtractErrorSummary {
    <#
    .SYNOPSIS
        Extracts a one-line summary from a multi-line error string.
    #>
    [CmdletBinding()]
    param([string]$ExtractError)

    if ([string]::IsNullOrWhiteSpace($ExtractError)) {
        return $null
    }

    $summary = $ExtractError
    $scriptMarker = $summary.IndexOf('; Script=', [System.StringComparison]::OrdinalIgnoreCase)
    if ($scriptMarker -ge 0) {
        $summary = $summary.Substring(0, $scriptMarker)
    }

    $newlineMarker = $summary.IndexOfAny(@([char]"`r", [char]"`n"))
    if ($newlineMarker -ge 0) {
        $summary = $summary.Substring(0, $newlineMarker)
    }

    return $summary.Trim()
}
