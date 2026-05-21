#Requires -Version 7
Import-Module 'C:\dev\winget-tools\WingetTools\WingetTools.psd1' -Force
$packages = Get-Content 'C:\dev\winget-tools\shards\shard-0008.txt'
$total = $packages.Count
$i = 0
foreach ($pkg in $packages) {
    $i++
    $pct = [math]::Round(($i / $total) * 100, 1)
    Write-Output "[$i/$total $pct%] Processing: $pkg"
    try {
        $pkg | Install-TrackedWingetPackage -TrackingDir 'C:\dev\winget-tools\tracking\shard-0008' -TimeoutSeconds 45
    } catch {
        Write-Output "[$i/$total] ERROR on $pkg : $_"
    }
}
Write-Output "DONE - Processed $i packages"
