$ErrorActionPreference = 'Stop';
$toolsDir   = "$(Split-Path -parent $MyInvocation.MyCommand.Definition)"

# The URL and Checksum will be automatically replaced by update.ps1
$url      = 'REPLACE_ME'
$checksum = 'REPLACE_ME'

$packageArgs = @{
  packageName   = 'my-awesome-app'
  unzipLocation = $toolsDir
  fileType      = 'exe'
  url           = $url
  checksum      = $checksum
  checksumType  = 'sha256'
  silentArgs    = '/S' # Update this based on the installer type (e.g. /VERYSILENT, /quiet, etc)
  validExitCodes= @(0, 3010, 1641)
  softwareName  = 'My Awesome App*'
}

Install-ChocolateyPackage @packageArgs
