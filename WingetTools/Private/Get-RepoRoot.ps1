function Get-RepoRoot {
    <#
    .SYNOPSIS
        Returns the root of the current git repository.
    #>
    [CmdletBinding()]
    param()

    $root = (& git rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or -not $root) {
        throw 'Run this script from inside the git repository.'
    }

    return $root.Trim()
}
