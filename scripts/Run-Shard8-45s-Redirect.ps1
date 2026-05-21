#Requires -Version 7
$outFile = 'C:\dev\winget-tools\tracking\shard-0008\stdout.log'
$errFile = 'C:\dev\winget-tools\tracking\shard-0008\stderr.log'
Import-Module 'C:\dev\winget-tools\WingetTools\WingetTools.psd1' -Force
Get-Content 'C:\dev\winget-tools\shards\shard-0008.txt' | Install-TrackedWingetPackage -TrackingDir 'C:\dev\winget-tools\tracking\shard-0008' -TimeoutSeconds 45
