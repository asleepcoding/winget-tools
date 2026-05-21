#Requires -Version 7
Import-Module 'C:\dev\winget-tools\WingetTools\WingetTools.psd1' -Force
Get-Content 'C:\dev\winget-tools\shards\shard-0008.txt' | Install-TrackedWingetPackage -TrackingDir 'C:\dev\winget-tools\tracking\shard-0008' -TimeoutSeconds 45
