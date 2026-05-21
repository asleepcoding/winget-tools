#Requires -Version 7
<#
.SYNOPSIS
    Installs a WinGet package while tracking and neutralizing system changes.
    Optionally extracts the application icon and writes a durable metadata entry
    under winget-app-icons/<PackageId>/.
.DESCRIPTION
    Thin wrapper around the WingetTools module function.
    See Install-TrackedWingetPackage for full documentation.

    When -ExtractIcon is specified, the script additionally:
      1. Calls Get-WinGetIcon.ps1 to extract the icon after a successful install.
      2. Copies the result to winget-app-icons/<PackageId>/app-icon.ico
      3. Writes winget-app-icons/<PackageId>/metadata.json matching the schema
         produced by Invoke-BulkIconExtraction.ps1.

    This is useful for local testing that needs the same output layout as CI
    extraction runs.
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
    [int] $TimeoutSeconds = 600,

    [Parameter(HelpMessage = 'After install, extract the icon and write metadata.json + app-icon.ico under -PackageStateRoot. This mirrors the CI extraction output contract.')]
    [switch] $ExtractIcon,

    [Parameter(HelpMessage = 'Root directory for per-package metadata and icon output. Default: winget-app-icons')]
    [string] $PackageStateRoot = 'winget-app-icons'
)

begin {
    $modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'WingetTools'
    Import-Module $modulePath -Force -ErrorAction Stop

    $repoRoot   = Split-Path -Parent $PSScriptRoot
    $iconScript = Join-Path $repoRoot 'scripts\Get-WinGetIcon.ps1'

    # Small inline helper — mirrors Format-ExceptionDetails without relying on a
    # private module function being explicitly exported.
    function script:Format-ExceptionInline {
        param([Parameter(Mandatory)] $ErrorRecord)
        $parts = New-Object System.Collections.Generic.List[string]
        $parts.Add($ErrorRecord.Exception.Message) | Out-Null
        if ($ErrorRecord.InvocationInfo -and $ErrorRecord.InvocationInfo.ScriptName) {
            $parts.Add(('Script={0}; Line={1}' -f $ErrorRecord.InvocationInfo.ScriptName, $ErrorRecord.InvocationInfo.ScriptLineNumber)) | Out-Null
        }
        return ($parts -join '; ')
    }
}

process {
    $startUtc = [DateTime]::UtcNow.ToString('o')
    $results  = New-Object System.Collections.Generic.List[object]

    foreach ($pkg in $PackageId) {
        if ([string]::IsNullOrWhiteSpace($pkg)) { continue }

        $params = @{
            PackageId       = $pkg
            Scope           = $Scope
            Force           = $Force
            TimeoutSeconds  = $TimeoutSeconds
            NoNeutralize    = $NoNeutralize
            NoInstall       = $NoInstall
        }
        if ($PSBoundParameters.ContainsKey('TrackingDir')) {
            $params['TrackingDir'] = $TrackingDir
        }

        $tracked = $null
        try {
            $tracked = Install-TrackedWingetPackage @params
        }
        catch {
            $tracked = [pscustomobject]@{
                PackageId       = $pkg
                InstallResult   = 'failed'
                InstallExitCode = $null
                Error           = Format-ExceptionInline -ErrorRecord $_
            }
        }

        $results.Add($tracked) | Out-Null

        if (-not $ExtractIcon) { continue }

        # -------------------------------------------------------------------
        # Extract icon and populate winget-app-icons
        # -------------------------------------------------------------------
        $pkgStateDir = Join-Path $repoRoot $PackageStateRoot $pkg
        $metadataPath = Join-Path $pkgStateDir 'metadata.json'
        $canonicalIcoPath = Join-Path $pkgStateDir 'app-icon.ico'
        [void](New-Item -ItemType Directory -Path $pkgStateDir -Force)

        # Preserve prior firstSeenUtc
        $prevFirstSeen = $null
        if (Test-Path -LiteralPath $metadataPath) {
            try {
                $prevMeta = Get-Content -LiteralPath $metadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $prevFirstSeen = $prevMeta.firstSeenUtc
            }
            catch { }
        }

        $firstSeen       = if ($prevFirstSeen) { $prevFirstSeen } else { $startUtc }
        $installResult   = $tracked.InstallResult
        $installOk       = $installResult -in @('success', 'already-installed')
        $iconFile        = $null
        $iconBytes       = 0
        $iconSha         = $null
        $extractError    = $null

        if ($installOk) {
            $tempOutDir = Join-Path $env:TEMP ('winget-icon-{0}' -f [guid]::NewGuid().ToString('N'))
            try {
                $null = & $iconScript -PackageId $pkg -OutDir $tempOutDir -Scope 'Both' -Force -DisableHeuristicFallback 2>&1
                $extractedFiles = @(Get-ChildItem -LiteralPath $tempOutDir -File -Include '*.ico', '*.png' -ErrorAction SilentlyContinue)
                if ($extractedFiles.Count -gt 0) {
                    # Prefer PNG (MSIX), otherwise largest ICO
                    $chosen = @($extractedFiles | Where-Object { $_.Extension -ieq '.png' } | Select-Object -First 1)
                    if (-not $chosen) {
                        $chosen = @($extractedFiles | Sort-Object -Property @{Expression = 'Length'; Descending = $true}, @{Expression = 'Name'; Descending = $false} | Select-Object -First 1)
                    }
                    Copy-Item -LiteralPath $chosen.FullName -Destination $canonicalIcoPath -Force
                    $iconFile  = $chosen.Name
                    $iconBytes = $chosen.Length
                    $iconSha   = (Get-FileHash -LiteralPath $canonicalIcoPath -Algorithm SHA256).Hash.ToLowerInvariant()
                }
            }
            catch {
                $extractError = Format-ExceptionInline -ErrorRecord $_
            }
            finally {
                if (Test-Path -LiteralPath $tempOutDir) {
                    Remove-Item -LiteralPath $tempOutDir -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }

        $hasIcon = Test-Path -LiteralPath $canonicalIcoPath
        $status = if ($hasIcon) { 'HasIcon' }
                   elseif ($extractError) { 'ExtractError' }
                   elseif (-not $installOk) { if ($installResult -eq 'failed') { 'InstallFailed' } else { 'NoIcon' } }
                   else { 'NoIcon' }

        $metadata = [ordered]@{
            schema                  = 1
            packageId               = $pkg
            resolvedPackageId       = $null
            status                  = $status
            hasIcon                 = $hasIcon
            firstSeenUtc            = $firstSeen
            lastCheckedUtc          = $startUtc
            lastUpdatedUtc          = if ($hasIcon) { $startUtc } else { $null }
            wingetVersion           = $null
            packageVersion          = $null
            manifestSha             = $null
            installerType           = $null
            alreadyInstalled        = ($installResult -eq 'already-installed')
            installedByThisRun      = ($installResult -eq 'success')
            installSeconds          = if ($tracked.InstallDurationSec) { $tracked.InstallDurationSec } else { 0 }
            extractSeconds          = 0
            uninstallSeconds        = 0
            durationSeconds         = if ($tracked.InstallDurationSec) { $tracked.InstallDurationSec } else { 0 }
            installExitCode         = if ($null -ne $tracked.InstallExitCode) { $tracked.InstallExitCode } else { $null }
            installTimedOut         = $false
            uninstallExitCode       = $null
            uninstallTimedOut       = $false
            failureCategory         = if ($installResult -eq 'failed') { 'Install' } else { $null }
            installAttemptTag       = 'tracked-install'
            extractAttemptCount     = if ($hasIcon -or $extractError) { 1 } else { 0 }
            extractAttemptScopes    = if ($hasIcon -or $extractError) { @('Both') } else { $null }
            extractFailureCategory  = $null
            iconCount               = if ($hasIcon) { 1 } else { 0 }
            iconBytes               = if ($hasIcon) { $iconBytes } else { 0 }
            appIconFile             = if ($hasIcon) { 'app-icon.ico' } else { $null }
            canonicalIconSourceName = if ($iconFile) { $iconFile } else { $null }
            canonicalIconBytes      = if ($hasIcon) { $iconBytes } else { $null }
            canonicalIconSha256     = $iconSha
            extractError            = $extractError
            installStdErr           = if ($tracked.InstallResult -eq 'failed' -and $tracked.Error) { $tracked.Error } else { $null }
            installAttempts         = if ($null -ne $tracked.InstallExitCode) {
                @([pscustomobject]@{
                    tag             = 'tracked-install'
                    exitCode        = $tracked.InstallExitCode
                    exitHex         = '0x{0:X8}' -f ([uint32]([int64]$tracked.InstallExitCode -band 0xffffffffL))
                    timedOut        = $false
                    errorName       = $null
                    failureCategory = if ($installResult -eq 'failed') { 'Install' } else { $null }
                })
            }
            else { $null }
            icons                   = if ($hasIcon) {
                @([pscustomobject]@{
                    name  = $iconFile
                    bytes = $iconBytes
                    sha256 = $iconSha
                })
            }
            else { $null }
            run                     = [ordered]@{
                startedAtUtc = $startUtc
                runId        = if ($env:GITHUB_RUN_ID) { $env:GITHUB_RUN_ID } else { $null }
                runAttempt   = if ($env:GITHUB_RUN_ATTEMPT) { $env:GITHUB_RUN_ATTEMPT } else { $null }
                repository   = if ($env:GITHUB_REPOSITORY) { $env:GITHUB_REPOSITORY } else { $null }
            }
            tracking                = if ($tracked.TrackingPath) {
                [pscustomobject]@{
                    trackingPath = $tracked.TrackingPath
                    counts       = $tracked.Counts
                }
            }
            else { $null }
        }

        $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
        if ($hasIcon) {
            Write-Host "  Catalog state written: $metadataPath ($($iconBytes) bytes)" -ForegroundColor Green
        }
        else {
            Write-Host "  Catalog state written: $metadataPath (no icon)" -ForegroundColor DarkGray
        }
    }
}

end {
    $results
}
