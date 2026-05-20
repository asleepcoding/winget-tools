#Requires -Version 7
<#
.SYNOPSIS
    Splits a Windows .ico file into its individual frames.
.DESCRIPTION
    Thin wrapper around the WingetTools module function.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position = 0)]
    [Alias('FullName', 'PSPath')]
    [string[]] $Path,

    [string] $OutDir,

    [ValidateSet('Bmp', 'Ico')]
    [string] $DibFormat = 'Bmp',

    [switch] $Force
)

begin {
    $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'WingetTools'
    Import-Module $modulePath -Force -ErrorAction Stop
}

process {
    $params = @{
        Path      = $Path
        DibFormat = $DibFormat
        Force     = $Force
    }
    if ($PSBoundParameters.ContainsKey('OutDir')) {
        $params['OutDir'] = $OutDir
    }

    Expand-Ico @params
}
