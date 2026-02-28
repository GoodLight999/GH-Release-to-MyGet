Import-Module Chocolatey-AU

# GitHub repository of the target software
$github_owner = "marticliment"
$github_repo = "UniGetUI"

function global:au_GetLatest {
    # Get the latest release from GitHub API
    $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$github_owner/$github_repo/releases/latest"
    $version = $releases.tag_name -replace '^v', '' # Remove 'v' prefix if present
    
    # Find the installer asset (e.g., .exe or .msi)
    # This regex is an example and should be adjusted based on the actual asset names
    $asset = $releases.assets | Where-Object { $_.name -match '\.exe$' }
    $url = $asset.browser_download_url

    if (-not $url) {
        Write-Warning "Could not find installer download URL in the latest release."
        return
    }

    $hash = Get-RemoteFilesHashes $url

    return @{
        Version = $version
        URL32 = $url
        Checksum32 = $hash.Checksum
    }
}

function global:au_SearchReplace {
    @{
        ".\tools\chocolateyInstall.ps1" = @{
            "(^[$]url\s*=\s*)'.*'"      = "`$1'$($Latest.URL32)'"
            "(^[$]checksum\s*=\s*)'.*'" = "`$1'$($Latest.Checksum32)'"
        }
    }
}

# Run the update process
Update-Package -NoCheckUrl
