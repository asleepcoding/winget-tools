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
    [int] $TimeoutSeconds = 600,

    [Parameter(HelpMessage = 'After install, extract the icon and write metadata.json + app-icon.ico under winget-app-icons/<PackageId>/.')]
    [switch] $ExtractIcon,

    [Parameter(HelpMessage = 'Root directory for per-package metadata and icon output. Default: winget-app-icons')]
    [string] $PackageStateRoot = 'winget-app-icons'
)

begin {
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' | Join-Path -ChildPath '..' | Join-Path -ChildPath '..' | Join-Path -ChildPath '..'))
    $wrapperScript = Join-Path $repoRoot 'scripts\Install-TrackedWingetPackage.ps1'
    if (-not (Test-Path -LiteralPath $wrapperScript)) {
        throw "Thin wrapper script not found: $wrapperScript"
    }
}

process {
    $params = @{
        PackageId      = $PackageId
        Scope          = $Scope
        Force          = $Force
        TimeoutSeconds = $TimeoutSeconds
        NoNeutralize   = $NoNeutralize
        NoInstall      = $NoInstall
        ExtractIcon    = $ExtractIcon
        PackageStateRoot = $PackageStateRoot
    }
    if ($PSBoundParameters.ContainsKey('TrackingDir')) {
        $params['TrackingDir'] = $TrackingDir
    }

    & $wrapperScript @params
}
