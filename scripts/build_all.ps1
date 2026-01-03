#!/usr/bin/env pwsh
#Requires -Version 7.0

# ============================================================================
# build_all.ps1 - Orchestrate Full Build for Windows & Android on Windows
# ============================================================================
#
# This script automates the entire build process for a local Windows environment:
# 1. Bootstraps dependencies (CoMaps, Boost, vcpkg) with smart caching.
# 2. Builds native C++ binaries for both Android and Windows.
# 3. Downloads required map data assets.
# 4. Deploys binaries to "prebuilt" locations.
# 5. Builds the final Flutter applications (APK and EXE).
#
# Usage:
#   .\scripts\build_all.ps1
#
# ============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir

# Import common bootstrap logic
Import-Module (Join-Path $scriptDir "BootstrapCommon.psm1") -Force

# Logging helper locally (overrides module if needed, or reuses)
function Write-LogHeader { param([string]$msg) Write-Host "`n=== $msg ===" -ForegroundColor Cyan }

Write-LogHeader "STARTING FULL LOCAL BUILD"

# ----------------------------------------------------------------------------
# 1. BOOTSTRAP
# ----------------------------------------------------------------------------
# This handles:
# - Caching (checking for .thirdparty.7z, extracting if found)
# - Cloning CoMaps (if no cache)
# - Patching
# - Building Boost headers
# - Generating data files
# - Copying assets to example/assets
Bootstrap-Full -RepoRoot $repoRoot -Platform all

# ----------------------------------------------------------------------------
# 2. BUILD NATIVE BINARIES
# ----------------------------------------------------------------------------
Write-LogHeader "Building Native Binaries (Android)"
& (Join-Path $scriptDir "build_binaries_android.ps1")
if ($LASTEXITCODE -ne 0) { throw "Android binaries build failed" }

Write-LogHeader "Building Native Binaries (Windows)"
& (Join-Path $scriptDir "build_binaries_windows.ps1")
if ($LASTEXITCODE -ne 0) { throw "Windows binaries build failed" }

# ----------------------------------------------------------------------------
# 3. DEPLOY BINARIES
# ----------------------------------------------------------------------------
Write-LogHeader "Deploying Binaries to Prebuilt Folders"

# Android
$androidPrebuilt = Join-Path $repoRoot "android\prebuilt"
$androidBuildOut = Join-Path $repoRoot "build\agus-binaries-android"
New-Item -ItemType Directory -Force -Path $androidPrebuilt | Out-Null
Write-Host "Copying Android binaries..."
Copy-Item -Path "$androidBuildOut\*" -Destination "$androidPrebuilt\" -Recurse -Force

# Windows
$windowsPrebuilt = Join-Path $repoRoot "windows\prebuilt\x64"
$windowsBuildOut = Join-Path $repoRoot "build\agus-binaries-windows\x64"
New-Item -ItemType Directory -Force -Path $windowsPrebuilt | Out-Null
Write-Host "Copying Windows binaries..."
Copy-Item -Path "$windowsBuildOut\*" -Destination "$windowsPrebuilt\" -Force

# ----------------------------------------------------------------------------
# 4. DOWNLOAD MAP DATA
# ----------------------------------------------------------------------------
Write-LogHeader "Checking/Downloading Map Data"
# Logic adapted from devops.yml to fetch recent maps
$mapDate = "241221" # December 21, 2024
$mapBaseUrl = "https://omaps.wfr.software/maps/$mapDate"
$assetsDir = Join-Path $repoRoot "example\assets\maps"
New-Item -ItemType Directory -Force -Path $assetsDir | Out-Null

$maps = @("World.mwm", "WorldCoasts.mwm", "Gibraltar.mwm")

foreach ($map in $maps) {
    $dest = Join-Path $assetsDir $map
    if (-not (Test-Path $dest)) {
        Write-Host "Downloading $map..."
        $url = "$mapBaseUrl/$map"
        Invoke-WebRequest -Uri $url -OutFile $dest
    } else {
        Write-Host "$map already exists."
    }
}

# Verify ICU data (should have been handled by bootstrap, but good to check)
if (-not (Test-Path (Join-Path $assetsDir "icudt75l.dat"))) {
    Write-Warning "icudt75l.dat missing! Bootstrap might have failed to copy it."
}

# ----------------------------------------------------------------------------
# 5. FLUTTER BUILD
# ----------------------------------------------------------------------------
Write-LogHeader "Building Flutter Apps"

Push-Location (Join-Path $repoRoot "example")
try {
    Write-Host "Running flutter pub get..."
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }

    Write-Host "Building Windows Executable..."
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }

    Write-Host "Building Android APK..."
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed" }

    Write-LogHeader "BUILD SUCCESSFUL"
    Write-Host "Windows EXE: example\build\windows\x64\runner\Release\agus_maps_flutter_example.exe" -ForegroundColor Green
    Write-Host "Android APK: example\build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green
}
finally {
    Pop-Location
}
