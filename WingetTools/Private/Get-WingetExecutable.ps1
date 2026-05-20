function Get-WingetExecutable {
    <#
    .SYNOPSIS
        Resolves the WinGet CLI executable name.
        Prefers 'pinget' when available; falls back to 'winget'.
    #>
    [CmdletBinding()]
    param()

    if (Get-Command pinget -ErrorAction SilentlyContinue) { return 'pinget' }
    if (Get-Command winget -ErrorAction SilentlyContinue) { return 'winget' }
    throw 'Neither pinget nor winget found in PATH.'
}
