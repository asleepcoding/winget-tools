function Install-TrackedWingetPackage {
    <#
    .SYNOPSIS
        Installs a WinGet package while tracking and neutralizing system changes.
    .DESCRIPTION
        Wraps winget/pinget install with comprehensive before/after system-state
        snapshots across seven dimensions: processes, services, autorun entries,
        scheduled tasks, ARP entries, PATH environment variables, and shortcuts.

        By default, all newly introduced artifacts are neutralized after install:
        new processes are killed, new services are disabled, new autorun entries
        and scheduled tasks are removed, PATH is restored, and shortcuts are
        deleted. This keeps the host clean for bulk-installing thousands of
        packages.

        Tracking data is written as JSON to <TrackingDir>/<PackageId>/tracking.json.
    .PARAMETER PackageId
        One or more WinGet package IDs to install. Accepts pipeline input.
    .PARAMETER TrackingDir
        Directory where per-package tracking JSON files are written.
        Defaults to <repo-root>/tracking.
    .PARAMETER NoNeutralize
        When set, skips all post-install neutralization. Only records diffs.
    .PARAMETER NoInstall
        When set, skips the actual winget install. Useful for testing snapshot
        logic against already-installed software.
    .PARAMETER Scope
        Forwarded to winget: User, Machine, or Both.
    .PARAMETER Force
        Forwarded to winget to force reinstall.
    .PARAMETER TimeoutSeconds
        Maximum seconds to wait for winget install. Default: 600.
    .EXAMPLE
        Install-TrackedWingetPackage -PackageId 'Git.Git'
    .EXAMPLE
        'Git.Git', 'Microsoft.PowerToys' | Install-TrackedWingetPackage -NoNeutralize
    .EXAMPLE
        Install-TrackedWingetPackage -PackageId 'Git.Git' -NoInstall
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]] $PackageId,

        [string] $TrackingDir = (Join-Path (Get-RepoRoot) 'tracking'),

        [switch] $NoNeutralize,
        [switch] $NoInstall,

        [ValidateSet('User', 'Machine', 'Both')]
        [string] $Scope = 'Both',

        [switch] $Force,
        [int] $TimeoutSeconds = 600
    )

    begin {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        $PSNativeCommandUseErrorActionPreference = $false

        $wingetExe = Get-WingetExecutable
        Write-Verbose "Using package manager: $wingetExe"

        if (-not (Test-Path -LiteralPath $TrackingDir)) {
            New-Item -ItemType Directory -Path $TrackingDir -Force | Out-Null
        }
    }

    process {
        foreach ($pkg in $PackageId) {
            if ([string]::IsNullOrWhiteSpace($pkg)) { continue }

            Write-Host "`n========================================"
            Write-Host "Package: $pkg"
            Write-Host "========================================"

            $result = [PSCustomObject]@{
                PackageId        = $pkg
                InstallResult    = 'unknown'
                InstallExitCode  = $null
                InstallDurationSec = 0
                TrackingPath     = $null
                Counts           = @{}
                Error            = $null
            }

            try {
                # -----------------------------------------------------------------
                # 1. Capture pre-install snapshots
                # -----------------------------------------------------------------
                Write-Host "  Capturing pre-install snapshots ..." -ForegroundColor Cyan
                $snapBefore = @{
                    Processes      = Get-ProcessSnapshot
                    Services       = Get-ServiceSnapshot
                    Autorun        = Get-AutorunSnapshot
                    ScheduledTasks = Get-ScheduledTaskSnapshot
                    Arp            = Get-ArpSnapshot
                    Path           = Get-PathSnapshot
                    Shortcuts      = Get-ShortcutSnapshot
                }

                # -----------------------------------------------------------------
                # 2. Run winget install (unless -NoInstall)
                # -----------------------------------------------------------------
                $installOutput = $null
                $installError  = $null
                $installExitCode = 0
                $startTime = Get-Date

                if (-not $NoInstall) {
                    if ($PSCmdlet.ShouldProcess($pkg, 'Install via winget')) {
                        $argsList = @(
                            'install',
                            '--id', $pkg,
                            '--silent',
                            '--accept-package-agreements',
                            '--accept-source-agreements',
                            '--disable-interactivity'
                        )
                        if ($Scope -ne 'Both') { $argsList += @('--scope', $Scope) }
                        if ($Force) { $argsList += '--force' }

                        Write-Host "  Installing via $wingetExe ..." -ForegroundColor Cyan
                        $psi = New-Object System.Diagnostics.ProcessStartInfo
                        $psi.FileName = $wingetExe
                        $psi.Arguments = $argsList -join ' '
                        $psi.RedirectStandardOutput = $true
                        $psi.RedirectStandardError = $true
                        $psi.UseShellExecute = $false
                        $psi.CreateNoWindow = $true

                        $proc = [System.Diagnostics.Process]::Start($psi)
                        $exited = $proc.WaitForExit([math]::Max($TimeoutSeconds * 1000, 1000))
                        if (-not $exited) {
                            $proc.Kill()
                            throw "Install timed out after $TimeoutSeconds seconds"
                        }

                        $installOutput = $proc.StandardOutput.ReadToEnd()
                        $installError  = $proc.StandardError.ReadToEnd()
                        $installExitCode = $proc.ExitCode

                        if ($installExitCode -eq 0) {
                            $result.InstallResult = 'success'
                            Write-Host "  Install OK" -ForegroundColor Green
                        } elseif ($installOutput -match 'already installed|Already installed') {
                            $result.InstallResult = 'already-installed'
                            Write-Host "  Already installed" -ForegroundColor Cyan
                        } else {
                            $result.InstallResult = 'failed'
                            $result.Error = "Exit code: $installExitCode; stderr: $installError"
                            Write-Host "  Install FAILED ($($result.Error))" -ForegroundColor Red
                        }
                    } else {
                        $result.InstallResult = 'whatif'
                        Write-Host "  WhatIf: skipped install" -ForegroundColor DarkGray
                    }
                } else {
                    $result.InstallResult = 'no-install'
                    Write-Host "  Skipped install (-NoInstall)" -ForegroundColor DarkGray
                }

                $result.InstallDurationSec = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
                $result.InstallExitCode = $installExitCode

                # -----------------------------------------------------------------
                # 3. Capture post-install snapshots
                # -----------------------------------------------------------------
                Write-Host "  Capturing post-install snapshots ..." -ForegroundColor Cyan
                $snapAfter = @{
                    Processes      = Get-ProcessSnapshot
                    Services       = Get-ServiceSnapshot
                    Autorun        = Get-AutorunSnapshot
                    ScheduledTasks = Get-ScheduledTaskSnapshot
                    Arp            = Get-ArpSnapshot
                    Path           = Get-PathSnapshot
                    Shortcuts      = Get-ShortcutSnapshot
                }

                # -----------------------------------------------------------------
                # 4. Compute diffs
                # -----------------------------------------------------------------
                $diffs = @{
                    Processes      = Get-ProcessDiff -Before $snapBefore.Processes -After $snapAfter.Processes
                    Services       = Get-ServiceDiff -Before $snapBefore.Services -After $snapAfter.Services
                    Autorun        = Get-AutorunDiff -Before $snapBefore.Autorun -After $snapAfter.Autorun
                    ScheduledTasks = Get-ScheduledTaskDiff -Before $snapBefore.ScheduledTasks -After $snapAfter.ScheduledTasks
                    Arp            = Get-ArpDiff -Before $snapBefore.Arp -After $snapAfter.Arp
                    Path           = Get-PathDiff -Before $snapBefore.Path -After $snapAfter.Path
                    Shortcuts      = Get-ShortcutDiff -Before $snapBefore.Shortcuts -After $snapAfter.Shortcuts
                }

                # Flatten counts for the result object
                $result.Counts = @{
                    Processes      = ($diffs.Processes | Measure-Object).Count
                    Services       = ($diffs.Services | Measure-Object).Count
                    Autorun        = ($diffs.Autorun | Measure-Object).Count
                    ScheduledTasks = ($diffs.ScheduledTasks | Measure-Object).Count
                    Arp            = ($diffs.Arp | Measure-Object).Count
                    PathMachine    = ($diffs.Path.Machine | Measure-Object).Count
                    PathUser       = ($diffs.Path.User | Measure-Object).Count
                    Shortcuts      = ($diffs.Shortcuts | Measure-Object).Count
                }

                # -----------------------------------------------------------------
                # 5. Write tracking report
                # -----------------------------------------------------------------
                $trackingPath = Write-TrackingReport `
                    -PackageId $pkg `
                    -TrackingDir $TrackingDir `
                    -Result $result `
                    -Diffs $diffs `
                    -InstallOutput $installOutput `
                    -InstallError $installError

                $result.TrackingPath = $trackingPath
                Write-Host "  Tracking report: $trackingPath" -ForegroundColor DarkGray

                # -----------------------------------------------------------------
                # 6. Neutralize (unless -NoNeutralize)
                # -----------------------------------------------------------------
                if (-not $NoNeutralize) {
                    Write-Host "  Neutralizing new artifacts ..." -ForegroundColor Cyan
                    Disable-NewProcesses -Diff $diffs.Processes
                    Disable-NewServices -Diff $diffs.Services
                    Remove-NewAutorunEntries -Diff $diffs.Autorun
                    Remove-NewScheduledTasks -Diff $diffs.ScheduledTasks
                    Restore-PathSnapshot -Snapshot $snapBefore.Path
                    Remove-NewShortcuts -Diff $diffs.Shortcuts
                    # ARP is recorded only, not uninstalled
                } else {
                    Write-Host "  Skipped neutralization (-NoNeutralize)" -ForegroundColor DarkGray
                }

            } catch {
                $result.InstallResult = 'failed'
                $result.Error = Format-ExceptionDetails -ErrorRecord $_
                Write-Host "  FAILED: $($result.Error)" -ForegroundColor Red
            }

            # Emit the result object
            $result
        }
    }

    end {
        Write-Verbose "Install-TrackedWingetPackage complete."
    }
}
