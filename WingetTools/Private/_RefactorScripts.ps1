#Requires -Version 7
<#
.SYNOPSIS
    Helper script to refactor scripts/*.ps1 into WingetTools module functions.
.DESCRIPTION
    Reads each original script, wraps its body in a function definition,
    writes it to WingetTools/Public/, and replaces the original with a thin wrapper.
#>

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$scriptsDir = Join-Path $repoRoot 'scripts'
$moduleDir = Join-Path $repoRoot 'WingetTools'
$publicDir = Join-Path $moduleDir 'Public'

$scriptMappings = @(
    @{ File = 'Get-WingetAppIconCatalog.ps1'; Function = 'Get-WingetAppIconCatalog' }
    @{ File = 'Get-WinGetIcon.ps1'; Function = 'Get-WinGetIcon' }
    @{ File = 'Get-WinGetManifest.ps1'; Function = 'Get-WinGetManifest' }
    @{ File = 'Install-WingetPackages.ps1'; Function = 'Install-WingetPackages' }
    @{ File = 'Invoke-BulkIconExtraction.ps1'; Function = 'Invoke-BulkIconExtraction' }
    @{ File = 'Invoke-IconExtractionCampaign.ps1'; Function = 'Invoke-IconExtractionCampaign' }
)

foreach ($mapping in $scriptMappings) {
    $scriptFile = $mapping.File
    $functionName = $mapping.Function
    $scriptPath = Join-Path $scriptsDir $scriptFile
    $modulePath = Join-Path $publicDir "$scriptFile"

    if (-not (Test-Path $scriptPath)) {
        Write-Warning "Script not found: $scriptPath"
        continue
    }

    Write-Host "Processing $scriptFile -> $functionName ..."

    # Read original script content
    $originalContent = Get-Content -LiteralPath $scriptPath -Raw -Encoding UTF8

    # Extract the param block (everything between 'param(' and its closing ')')
    # We need to find the param block and wrap it in a function
    # The script starts with comment-based help, then [CmdletBinding()], then param(...)

    # Find where the param block ends - we need to count parentheses
    $paramStart = $originalContent.IndexOf('param(')
    if ($paramStart -lt 0) {
        Write-Warning "No param block found in $scriptFile"
        continue
    }

    # Build the module function
    $functionHeader = @"
function $functionName {
    <#
    .SYNOPSIS
        $($scriptFile -replace '\.ps1$','') module function.
    #>
    [CmdletBinding()]
"@

    # Find the end of param block by counting parentheses
    $depth = 0
    $inString = $false
    $stringChar = $null
    $paramEnd = -1

    for ($i = $paramStart; $i -lt $originalContent.Length; $i++) {
        $c = $originalContent[$i]

        if ($inString) {
            if ($c -eq $stringChar -and $originalContent[$i - 1] -ne '\') {
                $inString = $false
            }
            continue
        }

        if ($c -eq '"' -or $c -eq "'") {
            $inString = $true
            $stringChar = $c
            continue
        }

        if ($c -eq '(') {
            $depth++
        } elseif ($c -eq ')') {
            $depth--
            if ($depth -eq 0) {
                $paramEnd = $i + 1
                break
            }
        }
    }

    if ($paramEnd -lt 0) {
        Write-Warning "Could not find end of param block in $scriptFile"
        continue
    }

    $paramBlock = $originalContent.Substring($paramStart, $paramEnd - $paramStart)
    $bodyContent = $originalContent.Substring($paramEnd).TrimStart()

    # Remove any 'Set-StrictMode' and '$ErrorActionPreference' from body since
    # the function will handle that
    $bodyContent = $bodyContent -replace '^Set-StrictMode\s+-Version\s+Latest\s*\r?\n', ''
    $bodyContent = $bodyContent -replace '^\$ErrorActionPreference\s*=\s*''Stop''\s*\r?\n', ''
    $bodyContent = $bodyContent -replace '^\$PSNativeCommandUseErrorActionPreference\s*=\s*\$false\s*\r?\n', ''

    # Build the complete function
    $functionContent = @"
$functionHeader
$paramBlock

    Set-StrictMode -Version Latest
    `$ErrorActionPreference = 'Stop'

$bodyContent
}
"@

    # Write module function
    Set-Content -LiteralPath $modulePath -Value $functionContent -Encoding UTF8
    Write-Host "  Written module function: $modulePath"

    # Create thin wrapper
    $wrapperContent = @"
#Requires -Version 7
<#
.SYNOPSIS
    $($scriptFile -replace '\.ps1$','') — thin wrapper around the WingetTools module function.
.DESCRIPTION
    Imports the WingetTools module and delegates to `$functionName.
#>

[CmdletBinding()]
param(
    # Parameters are forwarded dynamically via `$PSBoundParameters
)

`$modulePath = Join-Path (Split-Path -Parent `$PSScriptRoot) 'WingetTools'
Import-Module `$modulePath -Force -ErrorAction Stop

& `$functionName @PSBoundParameters
"@

    Set-Content -LiteralPath $scriptPath -Value $wrapperContent -Encoding UTF8
    Write-Host "  Replaced with wrapper: $scriptPath"
}

Write-Host "`nDone! Processed $($scriptMappings.Count) scripts."
