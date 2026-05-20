$ModuleRoot = $PSScriptRoot
$PrivatePath = Join-Path $ModuleRoot 'Private'
$PublicPath  = Join-Path $ModuleRoot 'Public'

# Load private functions
Get-ChildItem -Path $PrivatePath -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

# Load public functions
Get-ChildItem -Path $PublicPath -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
    ForEach-Object { . $_.FullName }

# Export public functions (match the names in the manifest)
Export-ModuleMember -Function @(
    'Expand-Ico'
    'Get-WingetAppIconCatalog'
    'Install-EssentialWingetPackages'
    'Install-TrackedWingetPackage'
    'Install-WingetPackages'
    'Uninstall-NonEssentialWingetPackages'
)
