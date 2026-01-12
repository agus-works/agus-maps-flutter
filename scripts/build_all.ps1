#!/usr/bin/env pwsh
#Requires -Version 7.0

# ============================================================================
# build_all.ps1 - Build All Platforms Using Dart Hooks
# ============================================================================
#
# This script builds agus_maps_flutter for Windows and Android.
#
# It uses the Dart build hooks (tool/build.dart) which handle:
# - Bootstrap (CoMaps clone, patches, Boost headers, data generation)
# - Building native binaries (Android, Windows)
#
# Usage:
#   .\scripts\build_all.ps1
#
# ============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir

# Logging helper
function Write-LogHeader { param([string]$msg) Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-LogStep { param([string]$msg) Write-Host "[STEP] $msg" -ForegroundColor Blue }
function Write-LogSuccess { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-LogError { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Write-LogWarn { param([string]$msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }

Write-LogHeader "BUILD ALL - Using Dart Hooks"

# ----------------------------------------------------------------------------
# Check Dependencies
# ----------------------------------------------------------------------------
Write-LogHeader "Checking Dependencies"

# Check Dart
try {
    $dartVersion = dart --version 2>&1 | Select-Object -First 1
    Write-Host "Dart: $dartVersion"
} catch {
    Write-LogError "Dart is not installed."
    Write-LogError "Install Dart: https://dart.dev/get-dart"
    exit 1
}

# Check Flutter
try {
    $flutterVersion = flutter --version 2>&1 | Select-Object -First 1
    Write-Host "Flutter: $flutterVersion"
} catch {
    Write-LogError "Flutter is not installed."
    Write-LogError "Install Flutter: https://docs.flutter.dev/get-started/install"
    exit 1
}

Write-LogSuccess "Dependencies check passed"

# ----------------------------------------------------------------------------
# Setup Flutter
# ----------------------------------------------------------------------------
Write-LogHeader "Setting Up Flutter"

Push-Location $repoRoot
try {
    Write-Host "Running flutter pub get..."
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }
}
finally {
    Pop-Location
}

Push-Location (Join-Path $repoRoot "example")
try {
    Write-Host "Running flutter pub get in example..."
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get in example failed" }
}
finally {
    Pop-Location
}

Write-LogSuccess "Flutter dependencies installed"

# ----------------------------------------------------------------------------
# Download Map Data (optional, for example app)
# ----------------------------------------------------------------------------
Write-LogHeader "Checking/Downloading Map Data"

$mapDate = "251212" # Default snapshot
$mapBaseUrl = "https://omaps.wfr.software/maps/$mapDate"
$assetsDir = Join-Path $repoRoot "example\assets\maps"
New-Item -ItemType Directory -Force -Path $assetsDir | Out-Null

$maps = @("World.mwm", "WorldCoasts.mwm", "Gibraltar.mwm")

foreach ($map in $maps) {
    $dest = Join-Path $assetsDir $map
    if (-not (Test-Path $dest)) {
        Write-Host "Downloading $map..."
        try {
            $url = "$mapBaseUrl/$map"
            Invoke-WebRequest -Uri $url -OutFile $dest -ErrorAction Stop
        } catch {
            Write-LogWarn "Failed to download $map"
        }
    } else {
        Write-Host "$map already exists."
    }
}

Write-LogSuccess "Map data ready"

# ----------------------------------------------------------------------------
# Build Native Binaries (Dart Hooks)
# ----------------------------------------------------------------------------
Write-LogHeader "Building Native Binaries (Dart Hooks)"

# This handles: bootstrap, building binaries
$env:AGUS_MAPS_BUILD_MODE = "contributor"

Write-LogStep "Building Android and Windows binaries..."
dart run tool/build.dart --build-binaries --platform android --platform windows

if ($LASTEXITCODE -ne 0) {
    throw "Native binaries build failed"
}

Write-LogSuccess "Native binaries built"

# ----------------------------------------------------------------------------
# Build Flutter Apps
# ----------------------------------------------------------------------------
Write-LogHeader "Building Flutter Example Apps"

Push-Location (Join-Path $repoRoot "example")
try {
    Write-LogStep "Building Android APK..."
    flutter build apk --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed" }

    Write-LogStep "Building Windows Executable..."
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows failed" }

    Write-LogHeader "BUILD SUCCESSFUL"
    Write-Host "Android APK: example\build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Green
    Write-Host "Windows EXE: example\build\windows\x64\runner\Release\agus_maps_flutter_example.exe" -ForegroundColor Green
}
finally {
    Pop-Location
}
