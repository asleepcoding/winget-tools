#Requires -Version 7
<#
.SYNOPSIS
    Installs WinGet packages from winget-database.json with host protection.
.DESCRIPTION
    Reads package IDs from winget-database.json and installs them sequentially using winget.
    After each install:
      - Resets PATH (Machine and User) to pre-install state to prevent PATH bloat
      - Disables any newly installed services
      - Kills any newly launched processes
    Stops when C: drive usage reaches or exceeds 80% or after N packages.
#>

param(
    [string]$DatabasePath = "c:\dev\winget-tools\unigetui\winget-database.json",
    [string]$LogPath = "c:\dev\winget-tools\install-log.json",
    [double]$MaxDiskPercent = 80.0,
    [int]$MaxPackages = 100,
    [int]$Skip = 0
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Get-DiskUsagePercent {
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DeviceID -eq 'C:' }
    if (-not $disk) { throw "Could not find C: drive" }
    return [math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 2)
}

function Read-Log {
    if (-not (Test-Path $LogPath)) { return @() }
    $content = Get-Content $LogPath -Raw
    if ([string]::IsNullOrWhiteSpace($content)) { return @() }
    $parsed = $content | ConvertFrom-Json
    if ($parsed -is [array]) { return $parsed }
    return @($parsed)
}

function Write-LogEntry {
    param([PSCustomObject]$Entry)
    $log = Read-Log
    $logList = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $log) { $logList.Add($item) }
    $logList.Add($Entry)
    $logList | ConvertTo-Json -Depth 10 | Set-Content $LogPath -Encoding UTF8
}

# ---------------------------------------------------------------------------
# PATH management
# ---------------------------------------------------------------------------

function Get-PathSnapshot {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
    return [PSCustomObject]@{
        Machine = $machinePath
        User    = $userPath
    }
}

function Restore-PathSnapshot {
    param([PSCustomObject]$Snapshot)
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

# ---------------------------------------------------------------------------
# Service management
# ---------------------------------------------------------------------------

function Get-ServiceSnapshot {
    return Get-Service | Select-Object Name, Status, StartType
}

function Disable-NewServices {
    param([array]$BeforeServices)
    $after = Get-ServiceSnapshot
    $beforeNames = $BeforeServices | ForEach-Object { $_.Name }
    $newServices = $after | Where-Object { $beforeNames -notcontains $_.Name }

    foreach ($svc in $newServices) {
        try {
            Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
            Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction Stop
            Write-Host "    [SERVICE] Disabled new service: $($svc.Name)" -ForegroundColor DarkYellow
        } catch {
            Write-Host "    [SERVICE] Failed to disable $($svc.Name): $_" -ForegroundColor DarkRed
        }
    }
    if (-not $newServices) {
        Write-Host "    [SERVICE] No new services detected" -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# Process management
# ---------------------------------------------------------------------------

function Get-ProcessSnapshot {
    return Get-Process | Select-Object Id, ProcessName, Path
}

function Kill-NewProcesses {
    param([array]$BeforeProcesses)
    $after = Get-ProcessSnapshot
    $beforeIds = $BeforeProcesses | ForEach-Object { $_.Id }
    $newProcs = $after | Where-Object { $beforeIds -notcontains $_.Id -and $_.ProcessName -notin @('pwsh','powershell','cmd','conhost','svchost','csrss','services','lsass','winlogon','dwm','fontdrvhost','msdtc','SearchIndexer','WmiPrvSE','dllhost','sihost','taskhostw','RuntimeBroker','ShellExperienceHost','StartMenuExperienceHost','TextInputHost','ctfmon','SecurityHealthService','smartscreen','WUDFHost','wlanext','spoolsv','smss','wininit','System','Registry','Memory Compression','Idle','Secure System','Registry') }

    foreach ($proc in $newProcs) {
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            Write-Host "    [PROCESS] Killed new process: $($proc.ProcessName) (PID $($proc.Id))" -ForegroundColor DarkYellow
        } catch {
            Write-Host "    [PROCESS] Failed to kill $($proc.ProcessName) (PID $($proc.Id)): $_" -ForegroundColor DarkRed
        }
    }
    if (-not $newProcs) {
        Write-Host "    [PROCESS] No new processes detected" -ForegroundColor DarkGray
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Write-Host "Loading package database from $DatabasePath ..."
$json = Get-Content $DatabasePath -Raw | ConvertFrom-Json
$allPackages = $json.packages.PSObject.Properties | ForEach-Object { $_.Value.winget } | Where-Object { $_ -ne $null }
$packages = $allPackages | Select-Object -Skip $Skip -First $MaxPackages

Write-Host "Found $($allPackages.Count) total packages. Will process $MaxPackages starting at offset $Skip."
Write-Host "Max disk usage threshold: $MaxDiskPercent%"
Write-Host "Starting installations...`n"

$installed = 0
$failed = 0
$skipped = 0
$stopReason = ""

foreach ($pkg in $packages) {
    $usedPercent = Get-DiskUsagePercent
    Write-Host "[Disk] C: drive usage: $usedPercent%"

    if ($usedPercent -ge $MaxDiskPercent) {
        $stopReason = "Disk threshold reached ($usedPercent% >= $MaxDiskPercent%)"
        Write-Host "STOPPING: $stopReason" -ForegroundColor Red
        break
    }

    Write-Host "Installing: $pkg ..." -NoNewline
    $startTime = Get-Date
    $result = "unknown"
    $errorMsg = $null

    # Capture pre-install state
    $pathSnapshot = Get-PathSnapshot
    $serviceSnapshot = Get-ServiceSnapshot
    $processSnapshot = Get-ProcessSnapshot

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "winget"
        $psi.Arguments = "install --id `"$pkg`" --silent --accept-package-agreements --accept-source-agreements --disable-interactivity"
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $proc.WaitForExit()

        $stdout = $proc.StandardOutput.ReadToEnd()
        $stderr = $proc.StandardError.ReadToEnd()

        if ($proc.ExitCode -eq 0) {
            $result = "success"
            Write-Host " OK" -ForegroundColor Green
        } elseif ($stdout -match "already installed" -or $stdout -match "Already installed") {
            $result = "already-installed"
            Write-Host " ALREADY INSTALLED" -ForegroundColor Cyan
        } else {
            $result = "failed"
            $errorMsg = "Exit code: $($proc.ExitCode); stderr: $stderr"
            Write-Host " FAILED ($errorMsg)" -ForegroundColor Yellow
        }
    } catch {
        $result = "failed"
        $errorMsg = $_.Exception.Message
        Write-Host " FAILED ($errorMsg)" -ForegroundColor Red
    }

    # Post-install cleanup
    Write-Host "  Cleaning up after $pkg ..."
    Restore-PathSnapshot -Snapshot $pathSnapshot
    Disable-NewServices -BeforeServices $serviceSnapshot
    Kill-NewProcesses -BeforeProcesses $processSnapshot

    $entry = [PSCustomObject]@{
        packageId   = $pkg
        result      = $result
        error       = $errorMsg
        diskBefore  = $usedPercent
        timestamp   = (Get-Date -Format "o")
        durationSec = ([math]::Round(((Get-Date) - $startTime).TotalSeconds, 1))
    }
    Write-LogEntry -Entry $entry

    if ($result -eq "success") { $installed++ }
    elseif ($result -eq "failed") { $failed++ }
    else { $skipped++ }

    Start-Sleep -Seconds 1
}

$finalDisk = Get-DiskUsagePercent
Write-Host "`n========================================"
Write-Host "Installation run complete."
Write-Host "Stop reason: $stopReason"
Write-Host "Final disk usage: $finalDisk%"
Write-Host "Installed: $installed"
Write-Host "Failed:    $failed"
Write-Host "Skipped:   $skipped"
Write-Host "Log file:  $LogPath"
Write-Host "========================================"
