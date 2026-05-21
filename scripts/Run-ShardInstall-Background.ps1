#Requires -Version 7
<#
.SYNOPSIS
    Runs a shard install in a background PowerShell process with file logging.
.DESCRIPTION
    Launches a hidden PowerShell process that logs all output to a file.
    Progress is tracked via the tracking directory.
    This avoids VS Code terminal crashes and console buffer issues.
.PARAMETER ShardFile
    Path to the shard text file containing package IDs (one per line).
.PARAMETER TrackingDir
    Directory where per-package tracking JSON files are written.
.PARAMETER TimeoutSeconds
    Maximum seconds to wait for each winget install. Default: 45.
.PARAMETER LogFile
    Path to a log file for real-time progress output.
.EXAMPLE
    .\Run-ShardInstall-Background.ps1 -ShardFile ..\shards\shard-0008.txt -TrackingDir ..\tracking\shard-0008 -TimeoutSeconds 45
#>
param(
    [Parameter(Mandatory)]
    [string] $ShardFile,

    [Parameter(Mandatory)]
    [string] $TrackingDir,

    [int] $TimeoutSeconds = 45,

    [string] $LogFile = ''
)

$ErrorActionPreference = 'Stop'

# Resolve paths to absolute
$ShardFile = Resolve-Path $ShardFile
$TrackingDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($TrackingDir)
if (-not $LogFile) {
    $LogFile = Join-Path $TrackingDir "install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
} else {
    $LogFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LogFile)
}

# Ensure tracking dir exists
if (-not (Test-Path $TrackingDir)) {
    New-Item -ItemType Directory -Path $TrackingDir -Force | Out-Null
}

# Build the command that runs in the background process
$command = @"
Import-Module 'C:\dev\winget-tools\WingetTools\WingetTools.psd1' -Force
`$packages = Get-Content '$ShardFile'
`$total = `$packages.Count
`$i = 0
foreach (`$pkg in `$packages) {
    `$i++
    `$pct = [math]::Round((`$i / `$total) * 100, 1)
    "[`$(Get-Date -Format 'HH:mm:ss')] [`$i/`$total `$pct%] Processing: `$pkg" | Out-File -FilePath '$LogFile' -Append -Encoding utf8
    try {
        `$result = `$pkg | Install-TrackedWingetPackage -TrackingDir '$TrackingDir' -TimeoutSeconds $TimeoutSeconds
        "[`$(Get-Date -Format 'HH:mm:ss')] -> Result: `$(`$result.InstallResult), Duration: `$(`$result.InstallDurationSec)s" | Out-File -FilePath '$LogFile' -Append -Encoding utf8
    } catch {
        "[`$(Get-Date -Format 'HH:mm:ss')] -> ERROR: `$_" | Out-File -FilePath '$LogFile' -Append -Encoding utf8
    }
}
"[`$(Get-Date -Format 'HH:mm:ss')] DONE: Processed `$i/`$total packages" | Out-File -FilePath '$LogFile' -Append -Encoding utf8
"@

Write-Host "Launching background PowerShell process..." -ForegroundColor Cyan
Write-Host "  Shard file:   $ShardFile" -ForegroundColor Gray
Write-Host "  Tracking dir: $TrackingDir" -ForegroundColor Gray
Write-Host "  Timeout:      ${TimeoutSeconds}s" -ForegroundColor Gray
Write-Host "  Log file:     $LogFile" -ForegroundColor Gray

# Start hidden PowerShell process with redirected output
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'pwsh.exe'
$psi.Arguments = "-Command `"$command`""
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true

$proc = [System.Diagnostics.Process]::Start($psi)

Write-Host "`nStarted background process PID: $($proc.Id)" -ForegroundColor Green
Write-Host "Monitor progress with:" -ForegroundColor Cyan
Write-Host "  Get-Content '$LogFile' -Tail 10" -ForegroundColor Yellow
Write-Host "  Get-ChildItem '$TrackingDir' -Directory | Measure-Object" -ForegroundColor Yellow
