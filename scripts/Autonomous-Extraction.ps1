# Continuous Shard Extraction Script
# Processes packages from shards 21-30 autonomously with periodic auto-commits

param(
    [int]$StartShard = 21,
    [int]$EndShard = 30,
    [int]$BatchSize = 5,
    [int]$CommitInterval = 25,  # Commit after every N packages processed
    [int]$RamCheckInterval = 5,  # Check RAM every N packages
    [int]$MinRamMB = 6000
)

$ErrorActionPreference = 'Continue'
$RepoRoot = 'C:\dev\winget-tools'
$PackageStateRoot = Join-Path $RepoRoot 'winget-app-icons'
$OutBase = Join-Path $RepoRoot 'out'

$logFile = Join-Path $RepoRoot 'out\extraction-log.txt'
function Write-Log {
    param([string]$Message)
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] $Message"
    Add-Content -Path $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue
    Write-Host $line
}

function Test-RAM {
    # FreePhysicalMemory can be misleadingly low on Windows because memory is cached.
    # The Available MBytes performance counter is what Windows reports as usable.
    try {
        $counter = Get-Counter '\Memory\Available MBytes' -ErrorAction Stop
        return [int]$counter.CounterSamples[0].CookedValue
    } catch {
        return [int]((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1KB)
    }
}

function Kill-Leaked {
    $sus = @('Grafana','java','memfiles','dsa','duplicati','gwc','nvt','aruba','Stardust')
    foreach ($s in $sus) {
        Get-Process -Name "*$s*" -ErrorAction SilentlyContinue | ForEach-Object { 
            try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } catch {} 
        }
    }
}

function Commit-Progress {
    param([string]$Msg)
    try {
        Set-Location $RepoRoot
        git add winget-app-icons/ -A *>$null
        git diff --cached --quiet *>$null
        if ($LASTEXITCODE -ne 0) {
            git commit -m "$Msg" --quiet *>$null
            git push --quiet *>$null
            Write-Log "Committed: $Msg"
        }
    } catch { Write-Log "Commit error: $_" }
}

# Count total remaining
$allPkgs = @()
for ($s = $StartShard; $s -le $EndShard; $s++) {
    $f = Join-Path $RepoRoot ("shards\shard-{0:D4}.txt" -f $s)
    @(Get-Content $f) | Where-Object { -not (Test-Path (Join-Path $PackageStateRoot "$_\metadata.json")) } | ForEach-Object { $allPkgs += $_ }
}

Write-Log ("Starting autonomous extraction: {0} packages, shards {1}-{2}" -f $allPkgs.Count, $StartShard, $EndShard)
Write-Log ("BatchSize={0}, CommitInterval={1}, MinRAM={2}MB" -f $BatchSize, $CommitInterval, $MinRamMB)

$processed = 0
$totalIcons = 0
$totalMeta = 0
$startProcessTime = Get-Date

for ($i = 0; $i -lt $allPkgs.Count; $i += $BatchSize) {
    $end = [math]::Min($i + $BatchSize - 1, $allPkgs.Count - 1)
    $batch = $allPkgs[$i..$end]
    $batchNum = [int]($i / $BatchSize) + 1
    $totalBatches = [math]::Ceiling($allPkgs.Count / $BatchSize)
    
    # RAM check
    if (($batchNum - 1) % $RamCheckInterval -eq 0) {
        $ram = Test-RAM
        if ($ram -lt $MinRamMB) {
            Write-Log "RAM low ({0:N0}MB). Killing leaked processes..." -f $ram
            Kill-Leaked
            Start-Sleep -Seconds 3
            $ram = Test-RAM
            Write-Log "RAM after cleanup: {0:N0}MB" -f $ram
            if ($ram -lt $MinRamMB) {
                Write-Log "RAM still dangerous. Pausing 60s."
                Start-Sleep -Seconds 60
            }
        }
    }
    
    $outDir = Join-Path $OutBase ("bg-batch-{0:D4}" -f $batchNum)

    # Use a temp file to pass the full array of package IDs reliably
    $batchFile = Join-Path $env:TEMP ("autonomous-batch-{0:D4}.txt" -f $batchNum)
    $batch | Set-Content -Path $batchFile -Encoding UTF8 -Force

    Write-Log ("[{0}/{1}] {2} packages" -f $batchNum, $totalBatches, $batch.Count)

    try {
        $summaryFile = Join-Path $outDir 'summary.json'
        $cmd = @"
& '$RepoRoot\scripts\Invoke-BulkIconExtraction.ps1' -PackageListFile '$batchFile' -PackageStateRoot '$PackageStateRoot' -OutDir '$outDir' -UninstallAfter -PerPackageTimeoutSeconds 600
"@
        $process = Start-Process -FilePath 'pwsh' -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-Command',
            $cmd
        ) -NoNewWindow -Wait -PassThru

        if (Test-Path $summaryFile) {
            $s = Get-Content $summaryFile | ConvertFrom-Json
            $batchIcons = @($s.Results | Where-Object { $_.Status -eq 'IconExtracted' }).Count
            $totalIcons += $batchIcons
            $totalMeta += @($s.Results).Count
            Write-Log ("  -> {0}/{1} icons" -f $batchIcons, $batch.Count)
        } else {
            Write-Log "  -> No summary file"
        }
    } catch {
        Write-Log ("  -> Error: {0}" -f $_.Exception.Message)
    } finally {
        if (Test-Path $batchFile) { Remove-Item $batchFile -Force -ErrorAction SilentlyContinue }
    }
    
    $processed += $batch.Count
    
    # Periodic commit
    if ($processed % $CommitInterval -eq 0 -or $i + $BatchSize -ge $allPkgs.Count) {
        $elapsed = (Get-Date) - $startProcessTime
        $msg = "Autonomous extraction: {0}/{1} pkgs, {2} icons, elapsed {3:N1}h" -f $processed, $allPkgs.Count, $totalIcons, $elapsed.TotalHours
        Commit-Progress -Msg $msg
    }
}

Write-Log "EXTRACTION COMPLETE: $processed packages processed, $totalIcons icons, $totalMeta metadata"
Commit-Progress -Msg "Autonomous extraction complete: $totalIcons icons / $totalMeta metadata"
