function Get-AutorunSnapshot {
    <#
    .SYNOPSIS
        Captures a snapshot of autorun entries from registry Run keys and Startup folders.
    .DESCRIPTION
        Reads the following locations:
          - HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run
          - HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run
          - HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run
          - Common Startup folder (All Users)
          - User Startup folder
        Returns structured objects for each entry.
    #>
    [CmdletBinding()]
    param()

    $entries = [System.Collections.Generic.List[object]]::new()

    # Registry Run keys
    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
    )

    foreach ($regPath in $regPaths) {
        if (-not (Test-Path -LiteralPath $regPath)) { continue }
        $props = Get-ItemProperty -LiteralPath $regPath -ErrorAction SilentlyContinue
        if (-not $props) { continue }
        $props.PSObject.Properties | Where-Object {
            $_.Name -notin @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider')
        } | ForEach-Object {
            $entries.Add([PSCustomObject]@{
                Location = $regPath
                Name     = $_.Name
                Value    = $_.Value
                Type     = 'Registry'
            })
        }
    }

    # Startup folders
    $startupFolders = @(
        [Environment]::GetFolderPath('CommonStartup'),
        [Environment]::GetFolderPath('Startup')
    )

    foreach ($folder in $startupFolders) {
        if (-not (Test-Path -LiteralPath $folder)) { continue }
        Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue | ForEach-Object {
            $entries.Add([PSCustomObject]@{
                Location = $folder
                Name     = $_.Name
                Value    = $_.FullName
                Type     = 'File'
            })
        }
    }

    return $entries
}

function Get-AutorunDiff {
    <#
    .SYNOPSIS
        Returns autorun entries that exist in After but not in Before.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array]$Before,
        [Parameter(Mandatory)] [array]$After
    )

    $beforeKeys = $Before | ForEach-Object { "$($_.Location)\$($_.Name)" }
    return @($After | Where-Object { "$($_.Location)\$($_.Name)" -notin $beforeKeys })
}

function Remove-NewAutorunEntries {
    <#
    .SYNOPSIS
        Removes newly created autorun entries.
    .DESCRIPTION
        Deletes registry values or startup-folder files based on the entry Type.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array]$Diff
    )

    foreach ($entry in $Diff) {
        try {
            if ($entry.Type -eq 'Registry') {
                Remove-ItemProperty -LiteralPath $entry.Location -Name $entry.Name -Force -ErrorAction Stop
                Write-Host "    [AUTORUN] Removed registry entry: $($entry.Location)\$($entry.Name)" -ForegroundColor DarkYellow
            } else {
                Remove-Item -LiteralPath $entry.Value -Force -ErrorAction Stop
                Write-Host "    [AUTORUN] Removed startup file: $($entry.Value)" -ForegroundColor DarkYellow
            }
        } catch {
            Write-Host "    [AUTORUN] Failed to remove $($entry.Name): $_" -ForegroundColor DarkRed
        }
    }
    if (-not $Diff) {
        Write-Host "    [AUTORUN] No new autorun entries detected" -ForegroundColor DarkGray
    }
}
