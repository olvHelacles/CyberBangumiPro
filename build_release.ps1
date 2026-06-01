<#
.SYNOPSIS
  Build CyberBangumi Pro Windows Release and package as ZIP.
#>

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

Write-Host "=== CyberBangumi Pro Build Script ===" -ForegroundColor Cyan
Write-Host ""

# --------------- 1. Read version ---------------
Write-Host "[1/4] Reading version..." -ForegroundColor Yellow
$PubspecPath = Join-Path $ScriptDir "pubspec.yaml"
if (-not (Test-Path $PubspecPath)) {
    Write-Error "pubspec.yaml not found: $PubspecPath"
    exit 1
}

$PubspecContent = Get-Content $PubspecPath -Raw
$VersionMatch = [regex]::Match($PubspecContent, '(?m)^version:\s*(\S+)')
if (-not $VersionMatch.Success) {
    Write-Error "Cannot parse version from pubspec.yaml"
    exit 1
}
$Version = $VersionMatch.Groups[1].Value.Trim()
Write-Host "  Version: $Version"

# --------------- 2. flutter pub get ---------------
Write-Host ""
Write-Host "[2/4] Installing dependencies (flutter pub get)..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter pub get failed"
    exit 1
}
Write-Host "  Dependencies installed" -ForegroundColor Green

# --------------- 3. flutter build windows --release ---------------
Write-Host ""
Write-Host "[3/4] Building Windows Release..." -ForegroundColor Yellow
flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter build windows --release failed"
    exit 1
}
Write-Host "  Build completed" -ForegroundColor Green

# --------------- 4. Clean and package ---------------
Write-Host ""
Write-Host "[4/4] Cleaning runtime files and packaging ZIP..." -ForegroundColor Yellow

$ReleaseDir = Join-Path $ScriptDir "build\windows\x64\runner\Release"
if (-not (Test-Path $ReleaseDir)) {
    Write-Error "Release output directory not found: $ReleaseDir"
    exit 1
}

# Remove runtime-generated data files
$RuntimeFiles = @(
    "app_state.json",
    "calendar_cache.json",
    "cover_cache"
)
foreach ($Item in $RuntimeFiles) {
    $Path = Join-Path $ReleaseDir $Item
    if (Test-Path $Path) {
        if (Test-Path -PathType Container $Path) {
            Remove-Item -Recurse -Force $Path
            Write-Host "  Removed directory: $Item"
        } else {
            Remove-Item -Force $Path
            Write-Host "  Removed file: $Item"
        }
    }
}

# Package ZIP
$OutputDir = Join-Path $ScriptDir "release"
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$ZipName = "cyberbangumi_pro-v${Version}-windows-x64.zip"
$ZipPath = Join-Path $OutputDir $ZipName

if (Test-Path $ZipPath) {
    Remove-Item -Force $ZipPath
}

Write-Host "  Packaging: $ZipName ..."
Compress-Archive -Path "$ReleaseDir\*" -DestinationPath $ZipPath
Write-Host "  Packaged" -ForegroundColor Green

# --------------- Done ---------------
Write-Host ""
Write-Host "=== Build successful ===" -ForegroundColor Cyan
Write-Host "  ZIP: $ZipPath"
Write-Host ""
Write-Host "  Contents:"
Write-Host "    Executable: cyber_bangumi_pro.exe"
Write-Host "    Engine DLL: flutter_windows.dll"
Write-Host "    Compiled code: data/app.so"
Write-Host "    Assets: data/flutter_assets/"
Write-Host ""
