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
        'pwsh','powershell','cmd','conhost','svchost','csrss','services',
        'lsass','winlogon','dwm','fontdrvhost','msdtc','SearchIndexer',
        'WmiPrvSE','WmiPrvSE.exe','dllhost','sihost','taskhostw','RuntimeBroker',
        'ShellExperienceHost','StartMenuExperienceHost','TextInputHost',
        'ctfmon','SecurityHealthService','smartscreen','smartscreen.exe','WUDFHost','wlanext',
        'spoolsv','smss','wininit','System','Registry','Memory Compression',
        'Idle','Secure System','MoUsoCoreWorker','MoUsoCoreWorker.exe',
        'rundll32','rundll32.exe','SearchProtocolHost','SearchProtocolHost.exe',
        'msiexec','msiexec.exe'
    )

    foreach ($proc in $Diff) {
        if ($proc.ProcessName -in $systemProcs) { continue }
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            Write-Host "    [PROCESS] Killed new process: $($proc.ProcessName) (PID $($proc.Id))" -ForegroundColor DarkYellow
        } catch {
            Write-Host "    [PROCESS] Failed to kill $($proc.ProcessName) (PID $($proc.Id)): $_" -ForegroundColor DarkRed
        }
    }
    if (-not $Diff) {
        Write-Host "    [PROCESS] No new processes detected" -ForegroundColor DarkGray
    }
}
