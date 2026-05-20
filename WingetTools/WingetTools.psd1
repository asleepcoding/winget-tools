@{
    RootModule           = 'WingetTools.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author               = 'Devolutions'
    CompanyName          = 'Devolutions'
    Copyright            = '(c) Devolutions. All rights reserved.'
    Description          = 'PowerShell utilities for working with WinGet packages, icon extraction, and campaign orchestration.'
    PowerShellVersion    = '7.0'
    CompatiblePSEditions = @('Core')

    FunctionsToExport    = @(
        'Expand-Ico'
        'Get-WingetAppIconCatalog'
        'Install-EssentialWingetPackages'
        'Install-WingetPackages'
        'Uninstall-NonEssentialWingetPackages'
    )

    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags       = @('winget', 'icons', 'package-manager', 'windows')
            LicenseUri = ''
            ProjectUri = ''
        }
    }
}
