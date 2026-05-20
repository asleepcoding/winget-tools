function Get-PathSnapshot {
    <#
    .SYNOPSIS
        Captures a snapshot of the Machine and User PATH environment variables.
    #>
    [CmdletBinding()]
    param()

    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')

    return [PSCustomObject]@{
        Machine = $machinePath
        User    = $userPath
        MachineDirs = if ($machinePath) { $machinePath -split ';' | Where-Object { $_ } } else { @() }
        UserDirs    = if ($userPath)    { $userPath -split ';' | Where-Object { $_ } } else { @() }
    }
}

function Get-PathDiff {
    <#
    .SYNOPSIS
        Returns PATH directories that were added between Before and After.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject]$Before,
        [Parameter(Mandatory)] [PSCustomObject]$After
    )

    $newMachine = @($After.MachineDirs | Where-Object { $_ -notin $Before.MachineDirs })
    $newUser    = @($After.UserDirs    | Where-Object { $_ -notin $Before.UserDirs })

    return [PSCustomObject]@{
        Machine = $newMachine
        User    = $newUser
    }
}

function Restore-PathSnapshot {
    <#
    .SYNOPSIS
        Restores Machine and User PATH to the values captured in the snapshot.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [PSCustomObject]$Snapshot
    )

    $current = Get-PathSnapshot
    $restored = $false

    if ($current.Machine -ne $Snapshot.Machine) {
        [Environment]::SetEnvironmentVariable('Path', $Snapshot.Machine, 'Machine')
        Write-Host "    [PATH] Restored Machine PATH ($($Snapshot.Machine.Length) chars)" -ForegroundColor DarkGray
        $restored = $true
    }
    if ($current.User -ne $Snapshot.User) {
        [Environment]::SetEnvironmentVariable('Path', $Snapshot.User, 'User')
        Write-Host "    [PATH] Restored User PATH ($($Snapshot.User.Length) chars)" -ForegroundColor DarkGray
        $restored = $true
    }
    if (-not $restored) {
        Write-Host "    [PATH] No change detected" -ForegroundColor DarkGray
    }
}
