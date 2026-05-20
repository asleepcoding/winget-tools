function Get-ArpSnapshot {
    <#
    .SYNOPSIS
        Captures a snapshot of Add/Remove Programs (ARP) entries from the registry.
    .DESCRIPTION
        Reads the Uninstall registry keys for 64-bit, 32-bit (WOW6432Node), and per-user entries.
        Returns structured objects for each installed program.
    #>
    [CmdletBinding()]
    param()

    $entries = [System.Collections.Generic.List[object]]::new()

    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($regPath in $regPaths) {
        if (-not (Test-Path -LiteralPath $regPath)) { continue }
        Get-ChildItem -LiteralPath $regPath -ErrorAction SilentlyContinue | ForEach-Object {
            $props = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            if (-not $props) { return }
            $entries.Add([PSCustomObject]@{
                KeyPath         = $_.PSPath
                DisplayName     = Get-OptionalPropertyValue -InputObject $props -Name 'DisplayName'
                DisplayVersion  = Get-OptionalPropertyValue -InputObject $props -Name 'DisplayVersion'
                Publisher       = Get-OptionalPropertyValue -InputObject $props -Name 'Publisher'
                InstallDate     = Get-OptionalPropertyValue -InputObject $props -Name 'InstallDate'
                UninstallString = Get-OptionalPropertyValue -InputObject $props -Name 'UninstallString'
                QuietUninstallString = Get-OptionalPropertyValue -InputObject $props -Name 'QuietUninstallString'
            })
        }
    }

    return $entries
}

function Get-ArpDiff {
    <#
    .SYNOPSIS
        Returns ARP entries that exist in After but not in Before.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array]$Before,
        [Parameter(Mandatory)] [array]$After
    )

    $beforeKeys = $Before | ForEach-Object { $_.KeyPath }
    return @($After | Where-Object { $_.KeyPath -notin $beforeKeys })
}
