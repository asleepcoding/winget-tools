#Requires -Version 7
<#
.SYNOPSIS
    Uninstalls all winget packages not on the essentials shortlist.
.DESCRIPTION
    Thin wrapper around the WingetTools module function.
#>

[CmdletBinding()]
param(
    [string]$ShortlistPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts\winget-essentials-shortlist.txt'),
    [switch]$Force
)

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'WingetTools'
Import-Module $modulePath -Force -ErrorAction Stop

$params = @{}
if ($PSBoundParameters.ContainsKey('ShortlistPath')) { $params['ShortlistPath'] = $ShortlistPath }
if ($Force) { $params['Force'] = $true }

Uninstall-NonEssentialWingetPackages @params
