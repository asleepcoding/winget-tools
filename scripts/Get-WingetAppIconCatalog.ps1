#Requires -Version 7
<#
.SYNOPSIS
    Queries the local winget-app-icons/ registry.
.DESCRIPTION
    Thin wrapper around the WingetTools module function.
#>

[CmdletBinding()]
param(
    [string]$PackageStateRoot = 'winget-app-icons',
    [string[]]$Status,
    [string]$PackageIdPattern,
    [switch]$HasIcon,
    [switch]$NoIcon,
    [string[]]$FailureCategory,
    [string[]]$ExtractFailureCategory,
    [string]$ExtractErrorPattern,
    [switch]$SummaryOnly,
    [switch]$IncludeSummary,
    [int]$TopReasonCount = 10
)

$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'WingetTools'
Import-Module $modulePath -Force -ErrorAction Stop

$params = @{}
if ($PSBoundParameters.ContainsKey('PackageStateRoot')) { $params['PackageStateRoot'] = $PackageStateRoot }
if ($PSBoundParameters.ContainsKey('Status'))           { $params['Status'] = $Status }
if ($PSBoundParameters.ContainsKey('PackageIdPattern')) { $params['PackageIdPattern'] = $PackageIdPattern }
if ($HasIcon)                                           { $params['HasIcon'] = $true }
if ($NoIcon)                                            { $params['NoIcon'] = $true }
if ($PSBoundParameters.ContainsKey('FailureCategory'))        { $params['FailureCategory'] = $FailureCategory }
if ($PSBoundParameters.ContainsKey('ExtractFailureCategory')) { $params['ExtractFailureCategory'] = $ExtractFailureCategory }
if ($PSBoundParameters.ContainsKey('ExtractErrorPattern'))    { $params['ExtractErrorPattern'] = $ExtractErrorPattern }
if ($SummaryOnly)                                       { $params['SummaryOnly'] = $true }
if ($IncludeSummary)                                    { $params['IncludeSummary'] = $true }
if ($PSBoundParameters.ContainsKey('TopReasonCount'))   { $params['TopReasonCount'] = $TopReasonCount }

Get-WingetAppIconCatalog @params
