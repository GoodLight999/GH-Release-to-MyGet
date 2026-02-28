param (
    [string]$TargetUrls
)

$ErrorActionPreference = 'Stop'

if (-not $TargetUrls) {
    Write-Host "TARGET_URLS variable is empty. Exiting."
    exit 0
}

# The TARGET_URLS may contain multiple URLs separated by newlines or commas.
# We normalize it to a string array.
$urls = $TargetUrls -split "`n|," | Where-Object { $_.Trim() -ne "" } | ForEach-Object { $_.Trim() }

Write-Host "Found $($urls.Count) URLs to process."

# Base directory for generating packages
$baseDir = "$(Get-Location)\packages"
if (-not (Test-Path $baseDir)) {
    New-Item -ItemType Directory -Path $baseDir | Out-Null
}

foreach ($rawurl in $urls) {
    try {
        # Check if URL has query parameters for advanced configuration (e.g. ?asset=*x86_64-w64-mingw32.exe.zip)
        $assetRegex = '\.(exe|msi|zip)$' # Default fallback
        $url = $rawurl
        
        if ($rawurl -match "\?asset=(.+)$") {
            # Convert user-friendly glob like "syncthingtray-*-x86_64-w64-mingw32.exe.zip" to regex
            $assetGlob = $matches[1]
            # Naive glob to regex
            $assetRegex = "^" + [Regex]::Escape($assetGlob).Replace("\*", ".*").Replace("\?", ".") + "$"
            $url = $rawurl -replace "\?.*$", ""
        }

        # Parse GitHub URL (e.g., https://github.com/jlcodes99/cockpit-tools)
        if ($url -notmatch "github\.com/([^/]+)/([^/]+)") {
            Write-Warning "Skipping invalid GitHub URL: $url"
            continue
        }
        
        $owner = $matches[1]
        $repo = $matches[2] -replace '\.git$', ''
        $packageId = $repo.ToLower()
        
        Write-Host ""
        Write-Host "============================"
        Write-Host "Processing: $owner/$repo"
        Write-Host "============================"
        
        $packageDir = Join-Path $baseDir $packageId
        $toolsDir = Join-Path $packageDir "tools"
        
        if (-not (Test-Path $toolsDir)) {
            New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
        }

        # 1. Fetch latest release info
        $apiUriLatest = "https://api.github.com/repos/$owner/$repo/releases/latest"
        $apiUriAll = "https://api.github.com/repos/$owner/$repo/releases"
        
        Write-Host "Fetching release info for $owner/$repo ..."
        $release = $null
        try {
            # Try to get the latest stable release first
            $release = Invoke-RestMethod -Uri $apiUriLatest
            Write-Host "Found stable release: $($release.tag_name)"
        } catch {
            Write-Host "No stable release found. Checking for pre-releases..."
            try {
                # Fallback to fetching all releases (includes pre-releases) and taking the first one
                $allReleases = Invoke-RestMethod -Uri $apiUriAll
                if ($allReleases.Count -gt 0) {
                    $release = $allReleases[0]
                    Write-Host "Found pre-release: $($release.tag_name)"
                } else {
                    Write-Warning "Repository has no releases at all."
                    continue
                }
            } catch {
                Write-Warning "Failed to fetch releases from $apiUriAll."
                continue
            }
        }

        $version = $release.tag_name -replace '^v', ''
        if (-not $version) {
            Write-Warning "Could not find a valid semantic version from tag: $($release.tag_name)."
            continue
        }
        # Find a suitable installer asset based on the regex
        $asset = $release.assets | Where-Object { $_.name -match $assetRegex } | Select-Object -First 1
        
        # Smart Auto-Detection Fallback: If no generic .exe/.msi/.zip was found and the user didn't specify a strict ?asset= glob
        if (-not $asset -and (-not $rawurl.Contains("?asset="))) {
            Write-Host "Generic asset match failed. Attempting smart Windows 64-bit GUI auto-detection..."
            
            # Step 1: Filter out things we definitely don't want (like .sig, .txt, linux, macos, arm, 386)
            $potentialAssets = $release.assets | Where-Object { 
                $_.name -notmatch '\.(sig|txt|json|asc|apk|tar\.(gz|xz)|AppImage|dmg)$' -and 
                ($_.name -match '(windows|w64|win64|win|x64)' -and $_.name -match '\.(exe|msi|zip)$') -and
                $_.name -notmatch '(arm|386|i686|linux|macos|mac|darwin)'
            }

            # Step 2: From the remaining Windows x64 assets, prefer GUI over CLI (exclude names with 'ctl', 'cli', or 'server')
            $asset = $potentialAssets | Where-Object { $_.name -notmatch '(ctl|cli|server)' } | Select-Object -First 1
            
            # Step 3: If still nothing, just grab whatever windows x64 asset we found first
            if (-not $asset) {
                $asset = $potentialAssets | Select-Object -First 1
            }
        }
        
        if (-not $asset) {
            Write-Warning "No suitable Windows asset found in the latest release ($version)."
            continue
        }

        $downloadUrl = $asset.browser_download_url
        $assetName = $asset.name
        $isZip = $assetName.EndsWith(".zip")
        $fileType = if ($isZip) { "zip" } else { $assetName.Split('.')[-1] }
        
        Write-Host "Resolved Version: $version"
        Write-Host "Resolved Asset URL: $downloadUrl"

        # 2. Calculate SHA256 Checksum
        # NEW: Check if the API provides the 'digest' natively so we can skip downloading massive files
        $checksumStr = $null
        if ($null -ne $asset.digest -and $asset.digest.StartsWith("sha256:")) {
            $checksumStr = $asset.digest.Substring(7).ToUpper()
            Write-Host "Extracted SHA256 checksum natively from GitHub API: $checksumStr"
        } else {
            Write-Host "No native digest found in API. Falling back to downloading $assetName to calculate hash..."
            $tempFile = Join-Path $env:TEMP $assetName
            try {
                Invoke-WebRequest -Uri $downloadUrl -OutFile $tempFile
                $hash = Get-FileHash -Path $tempFile -Algorithm SHA256
                $checksumStr = $hash.Hash
                Write-Host "Calculated Local Checksum ($fileType): $checksumStr"
            } catch {
                Write-Warning "Failed to download $downloadUrl for hashing."
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
                continue
            } finally {
                if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
            }
        }

        # 3. Generate .nuspec
        $nuspecContent = @"
<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2015/06/nuspec.xsd">
  <metadata>
    <id>$packageId</id>
    <version>$version</version>
    <title>$repo</title>
    <authors>$owner</authors>
    <projectUrl>$url</projectUrl>
    <tags>$packageId gui myget-auto</tags>
    <summary>Auto-generated package for $repo</summary>
    <description>This package was automatically published from $url</description>
  </metadata>
  <files>
    <file src="tools\**" target="tools" />
  </files>
</package>
"@
        $nuspecPath = Join-Path $packageDir "$packageId.nuspec"
        Set-Content -Path $nuspecPath -Value $nuspecContent -Encoding UTF8

        # 4. Generate chocolateyInstall.ps1
        $silentArgs = "/S"
        if ($fileType -eq "msi") {
            $silentArgs = "/qn /norestart"
        }

        if ($isZip) {
            # ZIP Installation Semantics: This is a standalone app, not an installer.
            # We should extract it to a persistent tools directory (C:\tools or similar) and create a Start Menu shortcut.
            $installScriptContent = @"
`$ErrorActionPreference = 'Stop';
`$toolsDir   = "`$(Split-Path -parent `$MyInvocation.MyCommand.Definition)"

# Chocolatey recommends putting standalone portable apps in `$env:ChocolateyToolsLocation` (usually C:\tools)
`$installDir = Join-Path (Get-ToolsLocation) '$packageId'

`$packageArgs = @{
  packageName   = '$packageId'
  unzipLocation = `$installDir
  url           = '$downloadUrl'
  checksum      = '$checksumStr'
  checksumType  = 'sha256'
}
Install-ChocolateyZipPackage @packageArgs

# Advanced Edge Case Handling: Find the main GUI executable to create a shortcut and ignore CLI shims
`$exes = Get-ChildItem -Path `$installDir -Recurse -Filter "*.exe"

`$guiCandidates = @()
foreach (`$exe in `$exes) {
    if (`$exe.Name -match "(ctl|cli|server)") {
        # It's a CLI tool or server component - tell Chocolatey NOT to create a path shim for it
        New-Item -ItemType File -Path "`$(`$exe.FullName).ignore" -Force | Out-Null
        Write-Host "Created ignore file for CLI/background tool: `$(`$exe.Name)"
    } else {
        `$guiCandidates += `$exe
    }
}

# 1. Sort candidates by length of name ascending (e.g. 'app.exe' is better than 'app-helper.exe')
`$guiCandidates = `$guiCandidates | Sort-Object { `$_.Name.Length }

`$mainExe = `$null
# 2. Prefer the shortest executable that contains the package name
foreach (`$candidate in `$guiCandidates) {
    if (`$candidate.Name.ToLower() -match '$packageId') {
        `$mainExe = `$candidate
        break
    }
}
# 3. If none matched the package name, just pick the shortest executable overall
if (-not `$mainExe -and `$guiCandidates.Count -gt 0) {
    `$mainExe = `$guiCandidates[0]
}

if (`$mainExe) {
    # Generate a proper Windows Start Menu shortcut for the user to launch the app!
    Write-Host "Setting up Start Menu shortcut for `$(`$mainExe.Name)"
    `$shortcutArgs = @{
        shortcutFilePath = Join-Path `$env:ProgramData "Microsoft\Windows\Start Menu\Programs\$repo.lnk"
        targetPath       = `$mainExe.FullName
        workingDirectory = `$mainExe.DirectoryName
        description      = "Launch $repo"
    }
    Install-ChocolateyShortcut @shortcutArgs
}
"@
        } else {
            # Standard executable/msi installer
            $installScriptContent = @"
`$ErrorActionPreference = 'Stop';
`$toolsDir   = "`$(Split-Path -parent `$MyInvocation.MyCommand.Definition)"

`$packageArgs = @{
  packageName   = '$packageId'
  unzipLocation = `$toolsDir
  fileType      = '$fileType'
  url           = '$downloadUrl'
  checksum      = '$checksumStr'
  checksumType  = 'sha256'
  silentArgs    = '$silentArgs'
  validExitCodes= @(0, 3010, 1641)
  softwareName  = '$repo*'
}

Install-ChocolateyPackage @packageArgs
"@
        }
        $installScriptPath = Join-Path $toolsDir "chocolateyInstall.ps1"
        Set-Content -Path $installScriptPath -Value $installScriptContent -Encoding UTF8

        # 5. Pack the package
        Write-Host "Packing Chocolatey package..."
        Push-Location $packageDir
        try {
            choco pack "$packageId.nuspec"
        } finally {
            Pop-Location
        }
        
        Write-Host "Successfully generated $packageId version $version"

    } catch {
        Write-Error "Error processing $url : $_"
    }
}

Write-Host "All generation complete."
