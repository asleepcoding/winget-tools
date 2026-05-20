#Requires -Version 7
<#
.SYNOPSIS
    Install missing winget packages from the essentials shortlist.
.DESCRIPTION
    Thin wrapper around the WingetTools module function.
#>

[CmdletBinding()]
param(
    [string]$ShortlistPath
)

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'WingetTools'
Import-Module $modulePath -Force -ErrorAction Stop

$params = @{}
if ($PSBoundParameters.ContainsKey('ShortlistPath')) {
    $params['ShortlistPath'] = $ShortlistPath
}

Install-EssentialWingetPackages @params
