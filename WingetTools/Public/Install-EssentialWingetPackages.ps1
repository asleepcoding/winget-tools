function Install-EssentialWingetPackages {
    <#
    .SYNOPSIS
        Install missing winget packages from the essentials shortlist.
    .DESCRIPTION
        Reads winget-essentials-shortlist.txt, checks which packages are already
        installed, and installs any missing ones via winget. Dependency packages
        (VCRedist, App Runtimes, etc.) are skipped since they are pulled in automatically.
    #>
    [CmdletBinding()]
    param(
        [string]$ShortlistPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'scripts\winget-essentials-shortlist.txt')
    )

    $ErrorActionPreference = 'Continue'

    if (-not (Test-Path $ShortlistPath)) {
        throw "Shortlist not found: $ShortlistPath"
    }

    # Parse shortlist — keep uncommented package IDs, skip dependency section
    $Lines = Get-Content $ShortlistPath
    $InDependencies = $false
    $PackageIds = foreach ($line in $Lines) {
        if ($line -match '^# --- Dependencies') {
            $InDependencies = $true
        }
        if ($InDependencies) { continue }
        if ($line -match '^\s*(\w+[\w.-]*\.[\w.-]+)') {
            $matches[1].Trim()
        }
    }
    $PackageIds = $PackageIds | Where-Object { $_ -ne '' } | Sort-Object -Unique

    Write-Host "=== Essentials shortlist ($($PackageIds.Count) packages) ===" -ForegroundColor Cyan
    $PackageIds | ForEach-Object { Write-Host "  $_" }

    # Get installed package IDs
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

    # Compute missing
    $Missing = $PackageIds | Where-Object { $InstalledIds -notcontains $_ } | Sort-Object

    Write-Host "`n=== Missing packages to INSTALL ($($Missing.Count)) ===" -ForegroundColor Green
    if ($Missing.Count -eq 0) {
        Write-Host "Everything is already installed!" -ForegroundColor Green
        return
    }

    $Missing | ForEach-Object { Write-Host "  INSTALL: $_" -ForegroundColor Green }

    # Confirm
    $confirm = Read-Host "`nProceed with install? [y/N]"
    if ($confirm -notin @('y','Y')) {
        Write-Host "Aborted. No packages were installed." -ForegroundColor Cyan
        return
    }

    # Install loop
    $Success = @()
    $Failed  = @()

    foreach ($pkg in $Missing) {
        Write-Host "`nInstalling $pkg ..." -ForegroundColor Green -NoNewline
        try {
            $result = winget install --id $pkg --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
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
    Write-Host "Installed: $($Success.Count)" -ForegroundColor Green
    Write-Host "Failed   : $($Failed.Count)" -ForegroundColor Red

    if ($Failed.Count -gt 0) {
        Write-Host "`nFailed packages:" -ForegroundColor Red
        $Failed | ForEach-Object { Write-Host "  - $_" }
    }
}
