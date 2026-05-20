function ConvertTo-CountMap {
    <#
    .SYNOPSIS
        Groups objects by a selector scriptblock and returns an ordered count map.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object[]]$InputObjects,
        [Parameter(Mandatory)] [scriptblock]$Selector,
        [switch]$Descending,
        [int]$Take = 0
    )

    $groups = @(
        $InputObjects |
            ForEach-Object { & $Selector $_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Group-Object |
            Sort-Object @{ Expression = 'Count'; Descending = $Descending.IsPresent }, Name
    )

    if ($Take -gt 0) {
        $groups = @($groups | Select-Object -First $Take)
    }

    $map = [ordered]@{}
    foreach ($group in $groups) {
        $map[$group.Name] = $group.Count
    }

    return [pscustomobject]$map
}
