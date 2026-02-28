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

        # 1. Fetch latest release info to get Version and check if there's an executable
        $apiUri = "https://api.github.com/repos/$owner/$repo/releases/latest"
        
        Write-Host "Fetching latest release from $apiUri ..."
        try {
            # Use basic header for rate limits if token is implicitly available, 
            # but public repos usually work fine without it for low volume.
            $release = Invoke-RestMethod -Uri $apiUri
        } catch {
            Write-Warning "Failed to fetch $apiUri. The repository might not have a release or is private."
            continue
        }

        $version = $release.tag_name -replace '^v', ''
        if (-not $version) {
            Write-Warning "Could not find a valid semantic version from tag: $($release.tag_name)."
            continue
        }

        # Smart Auto-Detection Fallback: If no generic .exe/.msi/.zip was found and the user didn't specify a strict ?asset= glob
        if (-not $asset -and (-not $rawurl.Contains("?asset="))) {
            Write-Host "Generic asset match failed. Attempting smart Windows 64-bit GUI auto-detection..."
            
            # Step 1: Filter out things we definitely don't want (like .sig, .txt, linux, macos, arm, 386)
            $potentialAssets = $release.assets | Where-Object { 
                $_.name -notmatch '\.(sig|txt|json|asc|apk|tar\.(gz|xz))$' -and 
                $_.name -match '(windows|w64|win64)' -and
                $_.name -match '(amd64|x64|x86_64)' -and
                $_.name -notmatch '(arm|386|i686)'
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

        # 2. Download and calculate Checksum
        $tempFilePath = Join-Path $env:TEMP $asset.name
        Write-Host "Downloading to calculate checksum..."
        Invoke-WebRequest -Uri $downloadUrl -OutFile $tempFilePath
        
        $checksumStr = (Get-FileHash -Path $tempFilePath -Algorithm SHA256).Hash
        Remove-Item -Path $tempFilePath -Force
        
        Write-Host "Calculated SHA256: $checksumStr"

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
            # If it's a ZIP file, Chocolatey should unzip it, typically using Install-ChocolateyZipPackage
            $installScriptContent = @"
`$ErrorActionPreference = 'Stop';
`$toolsDir   = "`$(Split-Path -parent `$MyInvocation.MyCommand.Definition)"

`$packageArgs = @{
  packageName   = '$packageId'
  unzipLocation = "`$env:ChocolateyInstall\lib\$packageId\tools"
  url           = '$downloadUrl'
  checksum      = '$checksumStr'
  checksumType  = 'sha256'
}
Install-ChocolateyZipPackage @packageArgs

# Optional: Create a shim (shortcut) if there is an exe inside the zip.
# It depends on the exact file structure inside the zip, but standard practice usually handles it if tools are placed correctly.
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
