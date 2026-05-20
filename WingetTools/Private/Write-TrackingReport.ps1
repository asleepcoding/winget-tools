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

        # Path diff is a PSCustomObject with Machine/User array properties
        if ($key -eq 'Path') {
            $report.counts[$key] = ($diffList.Machine.Count + $diffList.User.Count)
            $nested = @{
                Machine = @()
                User    = @()
            }
            foreach ($item in $diffList.Machine) {
                $ht = @{}
                $item.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
                $nested.Machine += $ht
            }
            foreach ($item in $diffList.User) {
                $ht = @{}
                $item.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
                $nested.User += $ht
            }
            $report.diffs[$key] = $nested
        } else {
            # All other diffs are flat arrays of PSCustomObjects
            $report.counts[$key] = ($diffList | Measure-Object).Count
            $serializable = @()
            foreach ($item in $diffList) {
                $ht = @{}
                if ($item -and $item.PSObject) {
                    $item.PSObject.Properties | ForEach-Object { $ht[$_.Name] = $_.Value }
                }
                $serializable += $ht
            }
            $report.diffs[$key] = $serializable
        }
    }

    $outPath = Join-Path $outDir 'tracking.json'
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $outPath -Encoding UTF8
    return $outPath
}
