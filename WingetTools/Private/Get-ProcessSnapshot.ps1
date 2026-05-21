function Get-ProcessSnapshot {
    <#
    .SYNOPSIS
        Captures a snapshot of all running processes.
    .DESCRIPTION
        Returns a list of process objects with Id, ProcessName, Path, and CommandLine.
        Uses CIM Win32_Process to obtain the command line.
    #>
    [CmdletBinding()]
    param()

    $cim = Get-CimInstance -ClassName Win32_Process -ErrorAction SilentlyContinue |
        Select-Object ProcessId, Name, ExecutablePath, CommandLine

    $snapshot = [System.Collections.Generic.List[object]]::new()
    foreach ($proc in $cim) {
        $snapshot.Add([PSCustomObject]@{
            Id          = $proc.ProcessId
            ProcessName = $proc.Name
            Path        = $proc.ExecutablePath
            CommandLine = $proc.CommandLine
        })
    }
    return $snapshot
}

function Get-ProcessDiff {
    <#
    .SYNOPSIS
        Returns processes that exist in After but not in Before.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array]$Before,
        [Parameter(Mandatory)] [array]$After
    )

    $beforeIds = $Before | ForEach-Object { $_.Id }
    return @($After | Where-Object { $beforeIds -notcontains $_.Id })
}

function Disable-NewProcesses {
    <#
    .SYNOPSIS
        Kills newly spawned processes.
    .DESCRIPTION
        Stops each process in the diff list with -Force.
        Skips critical system processes to avoid destabilizing the host.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array]$Diff
    )

    $systemProcs = @(
        'pwsh','pwsh.exe','powershell','powershell.exe','cmd','cmd.exe','conhost','conhost.exe',
        'svchost','svchost.exe','csrss','csrss.exe','services','services.exe',
        'lsass','lsass.exe','winlogon','winlogon.exe','dwm','dwm.exe',
        'fontdrvhost','fontdrvhost.exe','msdtc','msdtc.exe','SearchIndexer','SearchIndexer.exe',
        'WmiPrvSE','WmiPrvSE.exe','dllhost','dllhost.exe','sihost','sihost.exe',
        'taskhostw','taskhostw.exe','RuntimeBroker','RuntimeBroker.exe',
        'ShellExperienceHost','ShellExperienceHost.exe',
        'StartMenuExperienceHost','StartMenuExperienceHost.exe',
        'TextInputHost','TextInputHost.exe',
        'ctfmon','ctfmon.exe','SecurityHealthService','SecurityHealthService.exe',
        'smartscreen','smartscreen.exe','WUDFHost','WUDFHost.exe','wlanext','wlanext.exe',
        'spoolsv','spoolsv.exe','smss','smss.exe','wininit','wininit.exe',
        'System','Registry','Memory Compression','Idle','Secure System',
        'MoUsoCoreWorker','MoUsoCoreWorker.exe',
        'rundll32','rundll32.exe','SearchProtocolHost','SearchProtocolHost.exe',
        'msiexec','msiexec.exe','OpenConsole','OpenConsole.exe'
    )

    foreach ($proc in $Diff) {
        if ($proc.ProcessName -in $systemProcs) { continue }
        # Skip if process already exited
        $stillRunning = Get-Process -Id $proc.Id -ErrorAction SilentlyContinue
        if (-not $stillRunning) {
            Write-Host "    [PROCESS] Already exited: $($proc.ProcessName) (PID $($proc.Id))" -ForegroundColor DarkGray
            continue
        }
        # Skip processes in the current process tree to avoid killing ourselves
        $procAncestors = @()
        $current = Get-Process -Id $PID
        while ($current.Parent) {
            $procAncestors += $current.Parent.Id
            $current = $current.Parent
        }
        if ($proc.Id -in $procAncestors -or $proc.Id -eq $PID) {
            Write-Host "    [PROCESS] Skipped (in current process tree): $($proc.ProcessName) (PID $($proc.Id))" -ForegroundColor DarkGray
            continue
        }
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            Write-Host "    [PROCESS] Killed new process: $($proc.ProcessName) (PID $($proc.Id))" -ForegroundColor DarkYellow
        } catch {
            Write-Host "    [PROCESS] Failed to kill $($proc.ProcessName) (PID $($proc.Id)): $_" -ForegroundColor DarkRed
        }
    }
    if (-not $Diff) {
        Write-Host "    [PROCESS] No new processes detected" -ForegroundColor DarkGray
    }
}
