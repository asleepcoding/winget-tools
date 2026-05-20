function Get-ShortcutSnapshot {
    <#
    .SYNOPSIS
        Captures a snapshot of shortcuts in Desktop and Start Menu folders.
    .DESCRIPTION
        Scans the following locations for .lnk files:
          - User Desktop
          - Public Desktop
          - User Start Menu
          - ProgramData Start Menu
        Returns structured objects with target path, arguments, and working directory.
    #>
    [CmdletBinding()]
    param()

    $folders = @(
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('CommonDesktopDirectory'),
        [Environment]::GetFolderPath('StartMenu'),
        [Environment]::GetFolderPath('CommonStartMenu')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

    $shortcuts = [System.Collections.Generic.List[object]]::new()
    $shell = New-Object -ComObject WScript.Shell -ErrorAction SilentlyContinue

    foreach ($folder in $folders) {
        Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $targetPath = $null
            $arguments  = $null
            $workingDir = $null
            if ($shell) {
                try {
                    $shortcut = $shell.CreateShortcut($_.FullName)
                    $targetPath = $shortcut.TargetPath
                    $arguments  = $shortcut.Arguments
                    $workingDir = $shortcut.WorkingDirectory
                    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shortcut) | Out-Null
                } catch { }
            }
            $shortcuts.Add([PSCustomObject]@{
                FullPath        = $_.FullName
                TargetPath      = $targetPath
                Arguments       = $arguments
                WorkingDirectory = $workingDir
            })
        }
    }

    if ($shell) {
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
    }

    return $shortcuts
}

function Get-ShortcutDiff {
    <#
    .SYNOPSIS
        Returns shortcuts that exist in After but not in Before.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array]$Before,
        [Parameter(Mandatory)] [array]$After
    )

    $beforePaths = $Before | ForEach-Object { $_.FullPath }
    return @($After | Where-Object { $_.FullPath -notin $beforePaths })
}

function Remove-NewShortcuts {
    <#
    .SYNOPSIS
        Deletes newly created shortcuts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [array]$Diff
    )

    foreach ($shortcut in $Diff) {
        try {
            Remove-Item -LiteralPath $shortcut.FullPath -Force -ErrorAction Stop
            Write-Host "    [SHORTCUT] Removed: $($shortcut.FullPath)" -ForegroundColor DarkYellow
        } catch {
            Write-Host "    [SHORTCUT] Failed to remove $($shortcut.FullPath): $_" -ForegroundColor DarkRed
        }
    }
    if (-not $Diff) {
        Write-Host "    [SHORTCUT] No new shortcuts detected" -ForegroundColor DarkGray
    }
}
