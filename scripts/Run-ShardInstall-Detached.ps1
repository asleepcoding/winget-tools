#Requires -Version 7
<#
.SYNOPSIS
    Runs a shard install in a completely detached process outside VS Code.
.DESCRIPTION
    Launches a new PowerShell window to process all packages in a shard file.
    Progress is tracked via the tracking directory and an optional log file.
    This avoids VS Code terminal crashes on long-running output-heavy operations.
.PARAMETER ShardFile
    Path to the shard text file containing package IDs (one per line).
.PARAMETER TrackingDir
    Directory where per-package tracking JSON files are written.
.PARAMETER TimeoutSeconds
    Maximum seconds to wait for each winget install. Default: 45.
.PARAMETER LogFile
    Optional path to a log file for real-time progress output.
.PARAMETER WindowStyle
    PowerShell window style: Normal, Minimized, Hidden. Default: Normal.
.EXAMPLE
    .\Run-ShardInstall-Detached.ps1 -ShardFile ..\shards\shard-0008.txt -TrackingDir ..\tracking\shard-0008 -TimeoutSeconds 45
#>
param(
    [Parameter(Mandatory)]
    [string] $ShardFile,

    [Parameter(Mandatory)]
    [string] $TrackingDir,

    [int] $TimeoutSeconds = 45,

    [string] $LogFile = '',

    [ValidateSet('Normal', 'Minimized', 'Hidden')]
    [string] $WindowStyle = 'Normal'
)

$ErrorActionPreference = 'Stop'

# Resolve paths to absolute
$ShardFile = Resolve-Path $ShardFile
$TrackingDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TrackingDir)
if ($LogFile) {
    $LogFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogFile)
}

# Ensure tracking dir exists
if (-not (Test-Path $TrackingDir)) {
    New-Item -ItemType Directory -Path $TrackingDir -Force | Out-Null
}

# Build the inner script that runs in the detached window
$innerScript = @"
#Requires -Version 7
`$ErrorActionPreference = 'Stop'
`$modulePath = 'C:\dev\winget-tools\WingetTools\WingetTools.psd1'
Import-Module `$modulePath -Force

`$packages = Get-Content '$ShardFile'
`$total = `$packages.Count
`$i = 0

foreach (`$pkg in `$packages) {
    `$i++
    `$pct = [math]::Round((`$i / `$total) * 100, 1)
    `$msg = "[`$i/`$total `$pct%] Processing: `$pkg"
    Write-Host `$msg -ForegroundColor Yellow
    try {
        `$pkg | Install-TrackedWingetPackage -TrackingDir '$TrackingDir' -TimeoutSeconds $TimeoutSeconds | Out-Null
        Write-Host "  -> OK" -ForegroundColor Green
    } catch {
        Write-Host "  -> FAILED: `$_" -ForegroundColor Red
    }
}
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DONE: Processed `$i/`$total packages" -ForegroundColor Cyan
Write-Host "Tracking dir: $TrackingDir" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Read-Host "Press Enter to close"
"@

# Write inner script to temp file
$tempScript = Join-Path $TrackingDir "_shard-run-$(Get-Random).ps1"
$innerScript | Set-Content -Path $tempScript -Encoding UTF8

Write-Host "Launching detached PowerShell process..." -ForegroundColor Cyan
Write-Host "  Shard file:   $ShardFile" -ForegroundColor Gray
Write-Host "  Tracking dir: $TrackingDir" -ForegroundColor Gray
Write-Host "  Timeout:      ${TimeoutSeconds}s" -ForegroundColor Gray
Write-Host "  Temp script:  $tempScript" -ForegroundColor Gray

# Map WindowStyle to ProcessWindowStyle
$winStyleMap = @{
    'Normal'    = 'Normal'
    'Minimized' = 'Minimized'
    'Hidden'    = 'Hidden'
}

$proc = Start-Process -FilePath 'pwsh.exe' `
    -ArgumentList '-NoExit', '-Command', "& '$tempScript'" `
    -WindowStyle $winStyleMap[$WindowStyle] `
    -PassThru

Write-Host "`nStarted process PID: $($proc.Id)" -ForegroundColor Green
Write-Host "Monitor progress with:" -ForegroundColor Cyan
Write-Host "  Get-ChildItem '$TrackingDir' -Directory | Measure-Object" -ForegroundColor Yellow
