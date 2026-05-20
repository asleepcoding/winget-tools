function Uninstall-NonEssentialWingetPackages {
    <#
    .SYNOPSIS
        Uninstalls all winget packages not on the essentials shortlist.
    .DESCRIPTION
        Reads the essentials shortlist, compares against installed winget packages,
        and uninstalls anything not on the list. Dependency packages (VCRedist,
        App Runtimes, etc.) are preserved.
    #>
    [CmdletBinding()]
    param(
        [string]$ShortlistPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'scripts\winget-essentials-shortlist.txt'),
        [switch]$Force
    )

    $ErrorActionPreference = 'Continue'

    if (-not (Test-Path $ShortlistPath)) {
        throw "Shortlist not found: $ShortlistPath"
    }

    # Parse shortlist — keep all uncommented package IDs (including dependencies)
    $Lines = Get-Content $ShortlistPath
    $KeepIds = foreach ($line in $Lines) {
        if ($line -match '^\s*(\w+[\w.-]*\.[\w.-]+)') {
            $matches[1].Trim()
        }
    }
    $KeepIds = $KeepIds | Where-Object { $_ -ne '' } | Sort-Object -Unique

    Write-Host "=== Essentials shortlist ($($KeepIds.Count) packages) ===" -ForegroundColor Cyan
    $KeepIds | ForEach-Object { Write-Host "  KEEP: $_" }

    # Get installed winget packages (Id column only)
    Write-Host "`n=== Querying installed winget packages... ===" -ForegroundColor Cyan
    $InstalledRaw = winget list --source winget --disable-interactivity 2>$null

    $InstalledIds = $InstalledRaw |
        Select-Object -Skip 2 |
        ForEach-Object {
            if ($_ -match '^\S.*?\s{2,}(\S+?)\s{2,}') {
                $matches[1].Trim()
            }
        } |
        Where-Object { $_ -and $_ -notmatch '^\d+(\.\d+)*$' } |
        Sort-Object -Unique

    Write-Host "Found $($InstalledIds.Count) installed winget packages."

    # Compute removals
    $ToRemove = $InstalledIds | Where-Object { $KeepIds -notcontains $_ } | Sort-Object

    Write-Host "`n=== Packages to UNINSTALL ($($ToRemove.Count)) ===" -ForegroundColor Yellow
    if ($ToRemove.Count -eq 0) {
        Write-Host "Nothing to remove — your machine is already clean!" -ForegroundColor Green
        return
    }

    $ToRemove | ForEach-Object { Write-Host "  REMOVE: $_" -ForegroundColor Red }

    # Confirm
    if (-not $Force) {
        $confirm = Read-Host "`nProceed with uninstall? [y/N]"
        if ($confirm -notin @('y','Y')) {
            Write-Host "Aborted. No packages were removed." -ForegroundColor Cyan
            return
        }
    } else {
        Write-Host "`nForce mode: skipping confirmation." -ForegroundColor Yellow
    }

    # Uninstall loop
    $Success = @()
    $Failed  = @()

    foreach ($pkg in $ToRemove) {
        Write-Host "`nUninstalling $pkg ..." -ForegroundColor Yellow -NoNewline
        try {
            $result = winget uninstall --id $pkg --silent --disable-interactivity 2>&1
            $exitCode = $LASTEXITCODE
            if ($exitCode -eq 0) {
                Write-Host " OK" -ForegroundColor Green
                $Success += $pkg
            } else {
                Write-Host " FAILED (exit $exitCode)" -ForegroundColor Red
                $Failed += $pkg
            }
        } catch {
            Write-Host " FAILED: $_" -ForegroundColor Red
            $Failed += $pkg
        }
    }

    # Summary
    Write-Host "`n=== Summary ===" -ForegroundColor Cyan
    Write-Host "Removed : $($Success.Count)" -ForegroundColor Green
    Write-Host "Failed  : $($Failed.Count)" -ForegroundColor Red

    if ($Failed.Count -gt 0) {
        Write-Host "`nFailed packages:" -ForegroundColor Red
        $Failed | ForEach-Object { Write-Host "  - $_" }
    }
}
