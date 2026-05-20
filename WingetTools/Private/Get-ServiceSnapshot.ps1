function Get-ServiceSnapshot {
    <#
    .SYNOPSIS
        Captures a snapshot of all Windows services.
    #>
    [CmdletBinding()]
    param()

    return Get-Service | Select-Object Name, DisplayName, Status, StartType, @{N='PathName';E={
        try { (Get-CimInstance Win32_Service -Filter "Name='$($_.Name)'" -ErrorAction SilentlyContinue).PathName } catch { $null }
    }}
}

function Get-ServiceDiff {
    <#
    .SYNOPSIS
        Returns services that exist in After but not in Before.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array]$Before,
        [Parameter(Mandatory)] [array]$After
    )

    $beforeNames = $Before | ForEach-Object { $_.Name }
    return @($After | Where-Object { $beforeNames -notcontains $_.Name })
}

function Disable-NewServices {
    <#
    .SYNOPSIS
        Stops and disables newly created services.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array]$Diff
    )

    foreach ($svc in $Diff) {
        try {
            Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction Stop
            Write-Host "    [SERVICE] Disabled new service: $($svc.Name)" -ForegroundColor DarkYellow
        } catch {
            Write-Host "    [SERVICE] Failed to disable $($svc.Name): $_" -ForegroundColor DarkRed
        }
    }
    if (-not $Diff) {
        Write-Host "    [SERVICE] No new services detected" -ForegroundColor DarkGray
    }
}
