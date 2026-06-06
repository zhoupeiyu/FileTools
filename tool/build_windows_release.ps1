param(
  [string]$Configuration = "Release",
  [string]$OutputDir = "dist"
)

$ErrorActionPreference = "Stop"

Push-Location (Join-Path $PSScriptRoot "..")
try {
  if ($env:OS -ne "Windows_NT") {
    throw "Windows release builds must run on a Windows host."
  }

  flutter pub get
  flutter analyze
  flutter test
  flutter build windows --release

  $appDir = Join-Path "build\windows\x64\runner\$Configuration" ""
  $exePath = Join-Path $appDir "FileTools.exe"
  $gsPath = Join-Path $appDir "ghostscript\bin\gswin64c.exe"

  if (-not (Test-Path $exePath)) {
    throw "FileTools.exe was not created: $exePath"
  }
  if (-not (Test-Path $gsPath)) {
    throw "Bundled Ghostscript was not copied: $gsPath"
  }

  if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
  }

  $packageName = "FileTools-windows-x64.zip"
  $packagePath = Join-Path $OutputDir $packageName
  if (Test-Path $packagePath) {
    Remove-Item $packagePath -Force
  }

  Compress-Archive -Path (Join-Path $appDir "*") -DestinationPath $packagePath

  Write-Host "Windows release package created:"
  Write-Host (Resolve-Path $packagePath)
  Write-Host ""
  Write-Host "Executable inside package:"
  Write-Host "FileTools.exe"
}
finally {
  Pop-Location
}
