function Get-ScheduledTaskSnapshot {
    <#
    .SYNOPSIS
        Captures a snapshot of all scheduled tasks.
    #>
    [CmdletBinding()]
    param()

    try {
        return Get-ScheduledTask -ErrorAction SilentlyContinue | Select-Object TaskName, TaskPath, State, Author, URI, @{N='Triggers';E={
            ($_.Triggers | ForEach-Object { $_.CimClass.CimClassName }) -join ';'
        }}
    } catch {
        return @()
    }
}

function Get-ScheduledTaskDiff {
    <#
    .SYNOPSIS
        Returns scheduled tasks that exist in After but not in Before.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array]$Before,
        [Parameter(Mandatory)] [array]$After
    )

    $beforeKeys = $Before | ForEach-Object { "$($_.TaskPath)$($_.TaskName)" }
    return @($After | Where-Object { "$($_.TaskPath)$($_.TaskName)" -notin $beforeKeys })
}

function Remove-NewScheduledTasks {
    <#
    .SYNOPSIS
        Unregisters newly created scheduled tasks.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array]$Diff
    )

    foreach ($task in $Diff) {
        try {
            Unregister-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Confirm:$false -ErrorAction Stop
            Write-Host "    [SCHEDTASK] Removed scheduled task: $($task.TaskPath)$($task.TaskName)" -ForegroundColor DarkYellow
        } catch {
            Write-Host "    [SCHEDTASK] Failed to remove $($task.TaskName): $_" -ForegroundColor DarkRed
        }
    }
    if (-not $Diff) {
        Write-Host "    [SCHEDTASK] No new scheduled tasks detected" -ForegroundColor DarkGray
    }
}
