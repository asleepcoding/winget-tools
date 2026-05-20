#Requires -Version 7
<#
.SYNOPSIS
    Installs WinGet packages from winget-database.json with host protection.
.DESCRIPTION
    Thin wrapper around the WingetTools module function.
#>

[CmdletBinding()]
param(
    [string]$DatabasePath = "c:\dev\winget-tools\unigetui\winget-database.json",
    [string]$LogPath = "c:\dev\winget-tools\install-log.json",
    [double]$MaxDiskPercent = 80.0,
    [int]$MaxPackages = 100,
    [int]$Skip = 0
)

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'WingetTools'
Import-Module $modulePath -Force -ErrorAction Stop

$params = @{}
if ($PSBoundParameters.ContainsKey('DatabasePath'))   { $params['DatabasePath'] = $DatabasePath }
if ($PSBoundParameters.ContainsKey('LogPath'))          { $params['LogPath'] = $LogPath }
if ($PSBoundParameters.ContainsKey('MaxDiskPercent'))  { $params['MaxDiskPercent'] = $MaxDiskPercent }
if ($PSBoundParameters.ContainsKey('MaxPackages'))    { $params['MaxPackages'] = $MaxPackages }
if ($PSBoundParameters.ContainsKey('Skip'))           { $params['Skip'] = $Skip }

Install-WingetPackages @params
