#Requires -Version 7
<#
.SYNOPSIS
    Installs a WinGet package while tracking and neutralizing system changes.
.DESCRIPTION
    Thin wrapper around the WingetTools module function.
    See Install-TrackedWingetPackage for full documentation.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory, ValueFromPipeline)]
    [string[]] $PackageId,

    [string] $TrackingDir,

    [switch] $NoNeutralize,
    [switch] $NoInstall,

    [ValidateSet('User', 'Machine', 'Both')]
    [string] $Scope = 'Both',

    [switch] $Force,
    [int] $TimeoutSeconds = 600
)

begin {
    $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'WingetTools'
    Import-Module $modulePath -Force -ErrorAction Stop
}

process {
    $params = @{
        PackageId       = $PackageId
        Scope           = $Scope
        Force           = $Force
        TimeoutSeconds  = $TimeoutSeconds
        NoNeutralize    = $NoNeutralize
        NoInstall       = $NoInstall
    }
    if ($PSBoundParameters.ContainsKey('TrackingDir')) {
        $params['TrackingDir'] = $TrackingDir
    }

    Install-TrackedWingetPackage @params
}
