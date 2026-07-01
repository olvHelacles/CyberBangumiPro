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
Write-Host "[1/5] Reading version..." -ForegroundColor Yellow
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

# --------------- 2. Verify clash binary asset ---------------
Write-Host ""
Write-Host "[2/5] Verifying clash binary..." -ForegroundColor Yellow
$ClashAsset = Join-Path $ScriptDir "assets\mihomo.exe"
if (-not (Test-Path $ClashAsset)) {
    Write-Warning "mihomo.exe not found at assets\mihomo.exe"
    Write-Warning "Without it the built-in proxy will not function."
    Write-Warning "Run: curl -sL https://github.com/MetaCubeX/mihomo/releases/download/v1.19.27/mihomo-windows-amd64-compatible-v1.19.27.zip"
    Write-Host "  Continuing anyway..."
} else {
    $SizeMB = [math]::Round((Get-Item $ClashAsset).Length / 1MB, 1)
    Write-Host "  mihomo.exe: ${SizeMB}MB"
}

# --------------- 3. flutter pub get ---------------
Write-Host ""
Write-Host "[3/5] Installing dependencies (flutter pub get)..." -ForegroundColor Yellow
flutter pub get
if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter pub get failed"
    exit 1
}
Write-Host "  Dependencies installed" -ForegroundColor Green

# --------------- 4. flutter build windows --release ---------------
Write-Host ""
Write-Host "[4/5] Building Windows Release..." -ForegroundColor Yellow
flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    Write-Error "flutter build windows --release failed"
    exit 1
}
Write-Host "  Build completed" -ForegroundColor Green

# --------------- 5. Clean and package ---------------
Write-Host ""
Write-Host "[5/5] Cleaning runtime files and packaging ZIP..." -ForegroundColor Yellow

$ReleaseDir = Join-Path $ScriptDir "build\windows\x64\runner\Release"
if (-not (Test-Path $ReleaseDir)) {
    Write-Error "Release output directory not found: $ReleaseDir"
    exit 1
}

# Remove runtime-generated data files (they will be re-created on first launch).
# Keep app_state.json if present so the first run inherits proxy & subscription
# settings from the developer's environment.
$RuntimeFiles = @(
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

# Remove mihomo.exe from the release dir if it was extracted during a previous
# debug run — it will be re-extracted from the Flutter asset bundle at runtime.
$MihomoPath = Join-Path $ReleaseDir "mihomo.exe"
if (Test-Path $MihomoPath) {
    Remove-Item -Force $MihomoPath
    Write-Host "  Removed extracted: mihomo.exe"
}

# Copy app_state.json from project root as seed (if present).
$SeedState = Join-Path $ScriptDir "app_state.json"
$TargetState = Join-Path $ReleaseDir "app_state.json"
if (Test-Path $SeedState) {
    Copy-Item $SeedState $TargetState -Force
    Write-Host "  Seeded: app_state.json"
} elseif (-not (Test-Path $TargetState)) {
    Write-Warning "  No app_state.json found — first launch will use defaults."
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
Write-Host "  Size: $([math]::Round((Get-Item $ZipPath).Length / 1MB, 1))MB"
Write-Host ""
Write-Host "  Contents:"
Write-Host "    Executable: cyber_bangumi_pro.exe"
Write-Host "    Engine DLL: flutter_windows.dll"
Write-Host "    Clash core: data/flutter_assets/assets/mihomo.exe (extracted at runtime)"
Write-Host "    Config seed: app_state.json"
Write-Host ""
