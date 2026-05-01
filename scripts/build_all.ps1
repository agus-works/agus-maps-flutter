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

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir

# Logging helper
function Write-LogHeader { param([string]$msg) Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-LogStep { param([string]$msg) Write-Host "[STEP] $msg" -ForegroundColor Blue }
function Write-LogSuccess { param([string]$msg) Write-Host "[SUCCESS] $msg" -ForegroundColor Green }
function Write-LogError { param([string]$msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }
function Write-LogWarn { param([string]$msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-LogInfo { param([string]$msg) Write-Host "[INFO] $msg" -ForegroundColor White }
function Convert-ToAsciiLog {
    param([AllowNull()][object]$value)

    if ($null -eq $value) { return "" }

    $text = [string]$value
    $mojibakeBullet = [string][char]0x0393 + [string][char]0x00C7 + [string][char]0x00F3
    $text = $text -replace [regex]::Escape($mojibakeBullet), '-'
    $text = $text -replace [string][char]0x2022, '-'
    $text = $text -replace [string][char]0x00A9, '(c)'
    return $text -replace '[^\x00-\x7F]', '?'
}

function Invoke-PythonNative {
    param(
        [hashtable]$python,
        [string[]]$arguments
    )

    & $python['Executable'] @($python['Arguments']) @arguments
}

function Test-PythonProtobuf {
    param([hashtable]$python)

    $null = Invoke-PythonNative `
        -python $python `
        -arguments @('-c', 'import google.protobuf') `
        2>$null

    return $LASTEXITCODE -eq 0
}

Write-LogHeader "BUILD ALL - Using Dart Hooks"

# ----------------------------------------------------------------------------
# Check Dependencies
# ----------------------------------------------------------------------------
Write-LogHeader "Checking Dependencies"

# Check Dart
try {
    $dartVersion = dart --version 2>&1 | Select-Object -First 1
    Write-Host "Dart: $(Convert-ToAsciiLog $dartVersion)"
} catch {
    Write-LogError "Dart is not installed."
    Write-LogError "Install Dart: https://dart.dev/get-dart"
    exit 1
}

# Check Flutter
try {
    $flutterVersion = flutter --version 2>&1 | Select-Object -First 1
    Write-Host "Flutter: $(Convert-ToAsciiLog $flutterVersion)"
} catch {
    Write-LogError "Flutter is not installed."
    Write-LogError "Install Flutter: https://docs.flutter.dev/get-started/install"
    exit 1
}

# Check Python + protobuf
$pythonCmd = $null
if (Get-Command python -ErrorAction SilentlyContinue) {
    $pythonCmd = @{ Executable = 'python'; Arguments = @() }
} elseif (Get-Command py -ErrorAction SilentlyContinue) {
    $pythonCmd = @{ Executable = 'py'; Arguments = @('-3') }
}

if (-not $pythonCmd) {
    Write-LogError "Python 3 is not installed."
    Write-LogError "Install Python 3 to run CoMaps build tools (protobuf required)."
    exit 1
}

$pythonVersion = Invoke-PythonNative `
    -python $pythonCmd `
    -arguments @('--version') `
    2>&1 | Select-Object -First 1
Write-Host "Python: $(Convert-ToAsciiLog $pythonVersion)"

if (-not (Test-PythonProtobuf -python $pythonCmd)) {
    Write-LogWarn "Python 'protobuf' module is not installed. Installing it with pip..."
    Invoke-PythonNative `
        -python $pythonCmd `
        -arguments @('-m', 'pip', 'install', '--user', 'protobuf')

    if ($LASTEXITCODE -ne 0) {
        Write-LogError "Failed to install Python 'protobuf' module."
        Write-LogError "Install manually: python -m pip install --user protobuf"
        exit 1
    }

    if (-not (Test-PythonProtobuf -python $pythonCmd)) {
        Write-LogError "Python 'protobuf' module is still unavailable after installation."
        Write-LogError "Install manually: python -m pip install --user protobuf"
        exit 1
    }
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
# Download Map Data using Dart tool
# ----------------------------------------------------------------------------
Write-LogHeader "Downloading Map Data"

$assetsDir = Join-Path $repoRoot "example\assets\maps"
New-Item -ItemType Directory -Force -Path $assetsDir | Out-Null

Write-LogStep "Running Dart map downloader..."
Push-Location $repoRoot
try {
    dart run tool/map_downloader.dart `
        --output-dir $assetsDir `
        --files "World.mwm,WorldCoasts.mwm,Gibraltar.mwm" `
        --report (Join-Path $assetsDir "download_report.json") `
        --verbose
    if ($LASTEXITCODE -ne 0) { 
        Write-LogWarn "Map downloader returned non-zero exit code"
    }
}
finally {
    Pop-Location
}

# Copy ICU data if available
$icuSource = Join-Path $repoRoot "thirdparty\comaps\data\icudt75l.dat"
$icuDest = Join-Path $assetsDir "icudt75l.dat"
if ((Test-Path $icuSource) -and -not (Test-Path $icuDest)) {
    Copy-Item -Path $icuSource -Destination $icuDest
    Write-LogInfo "Copied ICU data to assets/maps/"
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
