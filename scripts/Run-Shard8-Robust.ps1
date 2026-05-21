#Requires -Version 7
$progressFile = 'C:\dev\winget-tools\tracking\shard-0008\progress.txt'
Import-Module 'C:\dev\winget-tools\WingetTools\WingetTools.psd1' -Force
$packages = Get-Content 'C:\dev\winget-tools\shards\shard-0008.txt'
$total = $packages.Count
$i = 0
foreach ($pkg in $packages) {
    $i++
    "$i/$total $pkg" | Out-File -FilePath $progressFile -Encoding utf8
    try {
        $pkg | Install-TrackedWingetPackage -TrackingDir 'C:\dev\winget-tools\tracking\shard-0008' -TimeoutSeconds 45
    } catch {
        "ERROR: $pkg : $_" | Out-File -FilePath $progressFile -Append -Encoding utf8
    }
}
"DONE: $i/$total" | Out-File -FilePath $progressFile -Encoding utf8
