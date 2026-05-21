#Requires -Version 7
$logFile = 'C:\dev\winget-tools\tracking\shard-0008\install.log'
Import-Module 'C:\dev\winget-tools\WingetTools\WingetTools.psd1' -Force
Get-Content 'C:\dev\winget-tools\shards\shard-0008.txt' | ForEach-Object {
    $pkg = $_
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Starting: $pkg"
    try {
        $pkg | Install-TrackedWingetPackage -TrackingDir 'C:\dev\winget-tools\tracking\shard-0008' -TimeoutSeconds 45
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - Completed: $pkg"
    } catch {
        Write-Host "$(Get-Date -Format 'HH:mm:ss') - ERROR on $pkg : $_"
    }
} *>&1 | Tee-Object -FilePath $logFile
