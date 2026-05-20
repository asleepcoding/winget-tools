function Write-TrackingReport {
    <#
    .SYNOPSIS
        Writes a per-package tracking report as JSON.
    .DESCRIPTION
        Serializes the before/after diffs for each tracked dimension into a single
        JSON file under <TrackingDir>/<SafePackageId>/tracking.json.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$PackageId,
        [Parameter(Mandatory)] [string]$TrackingDir,
        [Parameter(Mandatory)] [PSCustomObject]$Result,
        [Parameter(Mandatory)] [hashtable]$Diffs,
        [string]$InstallOutput = $null,
        [string]$InstallError = $null
    )

    $safeName = ConvertTo-SafeFileName -Name $PackageId
    $outDir   = Join-Path $TrackingDir $safeName
    if (-not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    $report = [ordered]@{
        packageId      = $PackageId
        timestamp      = (Get-Date -Format 'o')
        installResult  = $Result.InstallResult
        installExitCode = $Result.InstallExitCode
        installDurationSec = $Result.InstallDurationSec
        installOutput  = $InstallOutput
        installError   = $InstallError
        counts         = [ordered]@{}
        diffs          = [ordered]@{}
    }

    foreach ($key in $Diffs.Keys | Sort-Object) {
        $diffList = $Diffs[$key]

        # Handle nested PSCustomObject (e.g., Path diff with Machine/User sub-arrays)
        if ($diffList -isnot [array] -and $diffList -isnot [System.Collections.IList]) {
            $report.counts[$key] = 0
            $nested = @{}
            foreach ($prop in $diffList.PSObject.Properties) {
                $report.counts[$key] += ($prop.Value | Measure-Object).Count
                $nested[$prop.Name] = @()
                foreach ($item in $prop.Value) {
                    $ht = @{}
                    $item.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
                    $nested[$prop.Name] += $ht
                }
            }
            $report.diffs[$key] = $nested
        } else {
            $report.counts[$key] = $diffList.Count
            $serializable = @()
            foreach ($item in $diffList) {
                $ht = @{}
                $item.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
                $serializable += $ht
            }
            $report.diffs[$key] = $serializable
        }
    }

    $outPath = Join-Path $outDir 'tracking.json'
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outPath -Encoding UTF8
    return $outPath
}
