function Get-ManifestUrls {
    param([Parameter(Mandatory)] [string] $PackageId)

    $manifestScript = Join-Path $PSScriptRoot 'Get-WinGetManifest.ps1'
    if (-not (Test-Path $manifestScript)) { return $null }

    $json = $null
    try { $json = & $manifestScript -PackageId $PackageId -AsJson 2>$null } catch {}
    if (-not $json) { return $null }

    $manifest = $null
    try { $manifest = $json | ConvertFrom-Json } catch { return $null }

    $urls = New-Object System.Collections.Generic.List[string]
    foreach ($propName in @('PackageUrl', 'PublisherUrl', 'PublisherSupportUrl', 'LicenseUrl',
                            'PrivacyUrl', 'Homepage', 'ReleaseNotesUrl', 'CopyrightUrl')) {
        if ($manifest.PSObject.Properties.Name -contains $propName) {
            $val = [string]$manifest.$propName
            if (-not [string]::IsNullOrWhiteSpace($val) -and $val -match '^https?://') {
                [void]$urls.Add($val)
            }
        }
    }

    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $unique = New-Object System.Collections.Generic.List[string]
    foreach ($u in $urls) { if ($seen.Add($u)) { [void]$unique.Add($u) } }
    return $unique.ToArray()
}

function Get-GitHubRepoFromUrl {
    param([Parameter(Mandatory)] [string] $Url)

    $match = [regex]::Match($Url, 'github\.com/([^/]+)/([^/]+)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) { return $null }

    $owner = $match.Groups[1].Value.TrimEnd('.git')
    $repo  = $match.Groups[2].Value.TrimEnd('.git')
    if ([string]::IsNullOrWhiteSpace($owner) -or [string]::IsNullOrWhiteSpace($repo)) { return $null }
    return [pscustomobject]@{ Owner = $owner; Repo = $repo }
}

function Get-WebIconCandidates {
    param(
        [Parameter(Mandatory)] [string] $PackageId,
        $Hints,
        [int] $TimeoutSeconds = 15
    )

    $results = New-Object System.Collections.Generic.List[object]
    $urls = @(Get-ManifestUrls -PackageId $PackageId)
    if ($urls.Count -eq 0) { return ,$results.ToArray() }

    # --- GitHub repo icon probing ---
    $githubRepos = @()
    foreach ($url in $urls) {
        if ([string]::IsNullOrWhiteSpace($url) -or ($url -isnot [string])) { continue }
        $gh = Get-GitHubRepoFromUrl -Url $url
        if ($gh) { $githubRepos += $gh }
    }
    $githubRepos = $githubRepos | Select-Object Owner, Repo -Unique

    foreach ($repo in $githubRepos) {
        Write-Verbose ("Probing GitHub repo {0}/{1}..." -f $repo.Owner, $repo.Repo)
        $branches = @('main', 'master')
        try {
            $apiResp = Invoke-RestMethod -Uri ("https://api.github.com/repos/{0}/{1}" -f $repo.Owner, $repo.Repo) -TimeoutSec $TimeoutSeconds -ErrorAction Stop
            if ($apiResp.default_branch) { $branches = @(@($apiResp.default_branch)) }
        } catch { Write-Verbose ("  GitHub API failed: {0}" -f $_.Exception.Message) }

        $iconPaths = @(
            'icon.png', 'logo.png', 'app-icon.png',
            'assets/icon.png', 'assets/logo.png', 'assets/app-icon.png',
            'images/icon.png', 'images/logo.png', 'images/app-icon.png',
            '.github/icon.png', '.github/logo.png',
            'src/icon.png', 'src/logo.png',
            'resources/icon.png', 'resources/logo.png'
        )

        foreach ($branch in $branches) {
            foreach ($iconPath in $iconPaths) {
                $rawUrl = "https://raw.githubusercontent.com/{0}/{1}/{2}/{3}" -f $repo.Owner, $repo.Repo, $branch, $iconPath
                try {
                    $resp = Invoke-WebRequest -Uri $rawUrl -Method Head -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
                    $len = $resp.Headers['Content-Length']
                    $ct = $resp.Headers['Content-Type']
                    $isImage = $ct -match 'image/(png|jpeg|x-icon|vnd\.microsoft\.icon)'
                    if ($isImage -and ($len -eq $null -or [int]$len -gt 200) -and ($len -eq $null -or [int]$len -lt 5MB)) {
                        $results.Add([pscustomobject]@{ Path = $rawUrl; Index = 0; Reason = 'GitHubRepoIcon'; Priority = 5; IsUrl = $true }) | Out-Null
                        Write-Verbose ("  Found: {0} (type={1}, len={2})" -f $rawUrl, $ct, $len)
                    }
                } catch { }
            }
        }
    }

    # --- Website favicon probing ---
    $websiteRoots = @()
    foreach ($url in $urls) {
        if (-not (Get-GitHubRepoFromUrl -Url $url)) {
            try {
                $uri = [System.Uri]$url
                $root = "{0}://{1}" -f $uri.Scheme, $uri.Host
                if ($root -notin $websiteRoots) { $websiteRoots += $root }
            } catch { }
        }
    }

    foreach ($root in $websiteRoots) {
        foreach ($favPath in @('/favicon.ico', '/apple-touch-icon.png')) {
            $favUrl = $root + $favPath
            try {
                $resp = Invoke-WebRequest -Uri $favUrl -Method Head -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
                $len = $resp.Headers['Content-Length']
                $ct = $resp.Headers['Content-Type']
                if ($ct -match 'image' -and ($len -eq $null -or ([int]$len -ge 100 -and [int]$len -lt 1MB))) {
                    $results.Add([pscustomobject]@{ Path = $favUrl; Index = 0; Reason = 'WebsiteFavicon'; Priority = 10; IsUrl = $true }) | Out-Null
                    Write-Verbose ("  Found: {0} ({1} bytes)" -f $favUrl, $len)
                }
            } catch { }
        }
    }

    return $results.ToArray()
}

function Resolve-IconFromUrl {
    param(
        [Parameter(Mandatory)] [string] $Url,
        [string] $OutDir,
        [int] $TimeoutSeconds = 15
    )

    try {
        $resp = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSeconds -ErrorAction Stop
        $contentType = if ($resp.Headers['Content-Type']) { $resp.Headers['Content-Type'] } else { '' }
        $bytes = $resp.Content
        if (-not $bytes -or $bytes.Length -eq 0) { return $null }

        # PNG → ICO conversion
        if ($contentType -match 'image/png' -or $Url -match '\.png$') {
            $icoBytes = [WinGetIconTools.Native]::CreateIcoFromPng($bytes)
            if ($icoBytes -and $icoBytes.Length -gt 0) {
                if ($OutDir) {
                    $outFile = Join-Path $OutDir 'web-icon.ico'
                    [IO.File]::WriteAllBytes($outFile, $icoBytes)
                }
                return [pscustomobject]@{
                    Bytes    = $icoBytes
                    IconPath = if ($OutDir) { $outFile } else { $null }
                    IsUrl    = $true
                    Reason   = 'GitHubRepoIcon'
                }
            }
        }

        # ICO passthrough
        if ($contentType -match 'image/x-icon|image/vnd.microsoft.icon' -or $Url -match '\.ico$') {
            # Validate not generic
            $genericIconSha256 = @(
                '09233FAE9313121A350730FE15D6C62EE83116F14BB83511AD59004F78A1E342',
                'BBBEFD550BF8AF4F7A76FB8D99C01EA5045919223C9835EE9C1DFD6AB75D08CB',
                '1FE1B2D465347BB462A1DF2EAE0359A1461DD84E709581B5F26F6FB8654C2152',
                'E8852BDB05153EF8EF0748C28D0BF2D8F298B5EBB83E1E781A150A04B4AA7E05',
                'E21663E81163F1888F87E6ECB42EF3C7DC81647222E646C31F7E89D0FE70A01A',
                '657B28D4DF458B821466A5D32AB2C5C7F59C7B62C87D9E04579F16BE1211886F',
                '2EE43237D196100210F1786E7B73B57CD140F6013C072C70DBDFFD9E9BC695F8'
            )
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $hashHex = [BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-',''
            $sha.Dispose()

            if ($genericIconSha256 -contains $hashHex) {
                Write-Verbose ("[URL] Rejected generic icon from {0}" -f $Url)
                return $null
            }

            if ($OutDir) {
                $outFile = Join-Path $OutDir 'web-icon.ico'
                [IO.File]::WriteAllBytes($outFile, $bytes)
            }
            return [pscustomobject]@{
                Bytes    = $bytes
                IconPath = if ($OutDir) { $outFile } else { $null }
                IsUrl    = $true
                Reason   = 'WebsiteFavicon'
            }
        }
    } catch {
        Write-Verbose ("[URL] Failed to fetch icon from {0}: {1}" -f $Url, $_.Exception.Message)
    }
    return $null
}
