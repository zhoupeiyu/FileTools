param(
  [string]$Configuration = "Release",
  [string]$OutputDir = "dist",
  [string]$Version = ""
)

$ErrorActionPreference = "Stop"

function Get-InnoCompiler {
  $command = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
  if ($command) {
    return $command.Source
  }

  $candidates = @(
    (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
    (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
  )

  foreach ($candidate in $candidates) {
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  throw "Inno Setup compiler was not found. Install it with: choco install innosetup -y"
}

function Get-AppVersion {
  param([string]$ExplicitVersion)

  if (-not [string]::IsNullOrWhiteSpace($ExplicitVersion)) {
    return $ExplicitVersion
  }

  $pubspec = Get-Content "pubspec.yaml"
  foreach ($line in $pubspec) {
    if ($line -match "^version:\s*([0-9]+\.[0-9]+\.[0-9]+)") {
      return $Matches[1]
    }
  }

  return "1.0.0"
}

Push-Location (Join-Path $PSScriptRoot "..")
try {
  if ($env:OS -ne "Windows_NT") {
    throw "Windows installers must be built on a Windows host."
  }

  $appDir = Join-Path "build\windows\x64\runner\$Configuration" ""
  $exePath = Join-Path $appDir "FileTools.exe"
  $gsPath = Join-Path $appDir "ghostscript\bin\gswin64c.exe"

  if (-not (Test-Path $exePath)) {
    throw "Build output was not found. Run tool\build_windows_release.ps1 first: $exePath"
  }
  if (-not (Test-Path $gsPath)) {
    throw "Bundled Ghostscript was not copied: $gsPath"
  }

  if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir | Out-Null
  }

  $iscc = Get-InnoCompiler
  $resolvedAppDir = (Resolve-Path $appDir).Path
  $resolvedOutputDir = (Resolve-Path $OutputDir).Path
  $appVersion = Get-AppVersion -ExplicitVersion $Version
  $installerScript = "installer\windows\FileTools.iss"

  & $iscc `
    "/DSourceDir=$resolvedAppDir" `
    "/DOutputDir=$resolvedOutputDir" `
    "/DAppVersion=$appVersion" `
    $installerScript

  $installerPath = Join-Path $resolvedOutputDir "FileToolsSetup-$appVersion-x64.exe"
  if (-not (Test-Path $installerPath)) {
    throw "Installer was not created: $installerPath"
  }

  Write-Host "Windows installer created:"
  Write-Host $installerPath
}
finally {
  Pop-Location
}
