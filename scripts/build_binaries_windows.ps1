#Requires -Version 7.0
<#
.SYNOPSIS
    Build CoMaps native libraries for Windows.

.DESCRIPTION
    This script compiles the CoMaps native code for Windows using CMake and
    Visual Studio. It produces DLL files that can be used by the Flutter plugin.

    Output:
      - agus_maps_flutter.dll (~10MB) - Native CoMaps FFI library
      - zlib1.dll (~100KB) - Runtime dependency

.PARAMETER BuildType
    Build configuration: Release or Debug.
    Default: Release

.PARAMETER VcpkgRoot
    Path to vcpkg installation.
    Default: C:\vcpkg or $env:VCPKG_ROOT

.PARAMETER Clean
    Clean build directories before building.

.PARAMETER SkipArchive
    Skip creating the zip archive.

.EXAMPLE
    .\scripts\build_binaries_windows.ps1

.EXAMPLE
    .\scripts\build_binaries_windows.ps1 -BuildType Debug -Clean

.EXAMPLE
    .\scripts\build_binaries_windows.ps1 -VcpkgRoot D:\vcpkg

.NOTES
    This is the Windows equivalent of scripts/build_binaries_ios.sh for Windows.

    Prerequisites:
    - Visual Studio 2022 with C++ Desktop development workload
    - CMake 3.14+
    - Ninja (optional but recommended)
    - vcpkg with zlib installed
    - thirdparty/comaps must exist (run bootstrap.ps1 first)
#>

[CmdletBinding()]
param(
    [ValidateSet('Release', 'Debug')]
    [string]$BuildType = 'Release',
    [string]$VcpkgRoot = '',
    [switch]$Clean,
    [switch]$SkipArchive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$OutputDir = Join-Path $RepoRoot 'build\agus-binaries-windows'
$ComapsDir = Join-Path $RepoRoot 'thirdparty\comaps'
$SrcDir = Join-Path $RepoRoot 'src'

# Colors (Windows Terminal/PowerShell 7 support)
function Write-Step { param([string]$Message) Write-Host "[STEP] $Message" -ForegroundColor Blue }
function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Err { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

# Find vcpkg installation
function Find-Vcpkg {
    # Check explicit parameter
    if ($VcpkgRoot -and (Test-Path $VcpkgRoot)) {
        return $VcpkgRoot
    }
    
    # Check environment variable
    if ($env:VCPKG_ROOT -and (Test-Path $env:VCPKG_ROOT)) {
        return $env:VCPKG_ROOT
    }
    
    # Check common locations
    $commonPaths = @(
        "C:\vcpkg",
        "$env:USERPROFILE\vcpkg",
        "D:\vcpkg"
    )
    
    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    return $null
}

# Find CMake executable
function Find-CMake {
    # Try system CMake first
    $systemCmake = Get-Command cmake -ErrorAction SilentlyContinue
    if ($systemCmake) {
        return $systemCmake.Source
    }
    
    # Try Visual Studio CMake
    $vsPaths = @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
    )
    
    foreach ($path in $vsPaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    return $null
}

# Find Ninja executable
function Find-Ninja {
    # Try system Ninja
    $systemNinja = Get-Command ninja -ErrorAction SilentlyContinue
    if ($systemNinja) {
        return $systemNinja.Source
    }
    
    # Try Visual Studio Ninja
    $vsPaths = @(
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Enterprise\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Professional\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe",
        "${env:ProgramFiles}\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe",
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
    )
    
    foreach ($path in $vsPaths) {
        if (Test-Path $path) {
            return $path
        }
    }
    
    return $null
}

# Find Visual Studio installation and setup environment
function Initialize-VsEnvironment {
    Write-Step "Setting up Visual Studio environment..."
    
    # Try vswhere to find VS installation
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vswhere)) {
        Write-Warn "vswhere not found, attempting to use environment as-is"
        return $true
    }
    
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $vsPath) {
        Write-Err "Visual Studio with C++ tools not found"
        return $false
    }
    
    Write-Info "Found Visual Studio at: $vsPath"
    
    # Source the VS environment
    $vcvarsall = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path $vcvarsall)) {
        Write-Warn "vcvars64.bat not found, using environment as-is"
        return $true
    }
    
    # Execute vcvars64.bat and capture environment
    Write-Info "Initializing Visual Studio x64 environment..."
    $envOutput = cmd /c "`"$vcvarsall`" x64 >nul 2>&1 && set"
    foreach ($line in $envOutput) {
        if ($line -match "^([^=]+)=(.*)$") {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2], "Process")
        }
    }
    
    return $true
}

# Validate prerequisites
function Test-Prerequisites {
    Write-Step "Validating prerequisites..."
    
    # Check CoMaps source
    if (-not (Test-Path $ComapsDir)) {
        Write-Err "CoMaps source not found at: $ComapsDir"
        Write-Err "Run .\scripts\bootstrap.ps1 first"
        return $false
    }
    Write-Info "CoMaps source: $ComapsDir"
    
    # Find vcpkg
    $script:VcpkgPath = Find-Vcpkg
    if (-not $script:VcpkgPath) {
        Write-Err "vcpkg not found"
        Write-Err "Install vcpkg at C:\vcpkg or set VCPKG_ROOT environment variable"
        Write-Err "Run .\scripts\bootstrap.ps1 to install vcpkg"
        return $false
    }
    Write-Info "vcpkg: $script:VcpkgPath"
    
    # Check vcpkg zlib
    $zlibPath = Join-Path $script:VcpkgPath "installed\x64-windows\lib\zlib.lib"
    if (-not (Test-Path $zlibPath)) {
        Write-Err "zlib not installed in vcpkg"
        Write-Err "Run: vcpkg install zlib:x64-windows"
        return $false
    }
    Write-Info "zlib found in vcpkg"
    
    # Find CMake
    $script:CMakePath = Find-CMake
    if (-not $script:CMakePath) {
        Write-Err "CMake not found"
        Write-Err "Install CMake from https://cmake.org or via Visual Studio"
        return $false
    }
    Write-Info "CMake: $script:CMakePath"
    
    # Find Ninja (optional but recommended)
    $script:NinjaPath = Find-Ninja
    if ($script:NinjaPath) {
        Write-Info "Ninja: $script:NinjaPath"
    } else {
        Write-Warn "Ninja not found, will use Visual Studio generator (slower)"
    }
    
    return $true
}

# Bootstrap CoMaps dependencies (Boost headers)
function Initialize-ComapsDependencies {
    Write-Step "Checking CoMaps dependencies..."
    
    $boostDir = Join-Path $ComapsDir '3party\boost'
    $boostHeadersDir = Join-Path $boostDir 'boost'
    
    if (Test-Path $boostHeadersDir) {
        Write-Info "Boost headers already built"
        return
    }
    
    Write-Info "Building boost headers..."
    Push-Location $boostDir
    try {
        $bootstrapBat = Join-Path $boostDir 'bootstrap.bat'
        
        if (Test-Path $bootstrapBat) {
            & cmd /c $bootstrapBat 2>&1 | Out-Null
            $b2 = Join-Path $boostDir 'b2.exe'
            if (Test-Path $b2) {
                & $b2 headers 2>&1 | Out-Null
            }
        }
    } finally {
        Pop-Location
    }
    
    if (Test-Path $boostHeadersDir) {
        Write-Info "Boost headers ready"
    } else {
        Write-Warn "Boost headers may not be built - build might fail"
    }
}

# Build Windows binaries
function Build-Windows {
    $buildDir = Join-Path $RepoRoot "build\windows-x64"
    $arch = "x64"
    
    Write-Step "Building for Windows $arch"
    
    # Clean build directory if requested
    if ($Clean -and (Test-Path $buildDir)) {
        Write-Info "Cleaning build directory..."
        Remove-Item -Path $buildDir -Recurse -Force
    }
    
    # Create build directory
    New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
    
    # vcpkg toolchain
    $toolchainFile = Join-Path $script:VcpkgPath "scripts\buildsystems\vcpkg.cmake"
    
    # Configure CMake
    Write-Info "Configuring CMake for Windows $arch..."
    
    $cmakeArgs = @(
        '-B', $buildDir,
        '-S', $SrcDir,
        "-DCMAKE_TOOLCHAIN_FILE=$toolchainFile",
        "-DVCPKG_TARGET_TRIPLET=x64-windows",
        "-DCMAKE_BUILD_TYPE=$BuildType"
    )
    
    # Add Ninja generator if available
    if ($script:NinjaPath) {
        $cmakeArgs += @('-G', 'Ninja')
        $cmakeArgs += "-DCMAKE_MAKE_PROGRAM=$($script:NinjaPath)"
    } else {
        # Use Visual Studio generator
        $cmakeArgs += @('-G', 'Visual Studio 17 2022', '-A', 'x64')
    }
    
    & $script:CMakePath @cmakeArgs 2>&1 | ForEach-Object { 
        if ($_ -match 'error|Error|ERROR') {
            Write-Host $_ -ForegroundColor Red
        } elseif ($_ -match 'warning|Warning|WARNING') {
            Write-Host $_ -ForegroundColor Yellow
        } else {
            Write-Host $_ -ForegroundColor DarkGray
        }
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Err "CMake configuration failed"
        return $false
    }
    
    # Build
    Write-Info "Building Windows $arch..."
    $buildArgs = @('--build', $buildDir, '--config', $BuildType, '--parallel')
    
    & $script:CMakePath @buildArgs 2>&1 | ForEach-Object {
        if ($_ -match 'error|Error|ERROR') {
            Write-Host $_ -ForegroundColor Red
        } elseif ($_ -match 'warning|Warning|WARNING') {
            Write-Host $_ -ForegroundColor Yellow
        } else {
            Write-Host $_ -ForegroundColor DarkGray
        }
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Err "Build failed"
        return $false
    }
    
    # Copy output
    $abiOutputDir = Join-Path $OutputDir $arch
    New-Item -ItemType Directory -Force -Path $abiOutputDir | Out-Null
    
    # Find the built DLL (might be in $buildDir or $buildDir/$BuildType for VS generator)
    $dllName = 'agus_maps_flutter.dll'
    $dllPaths = @(
        (Join-Path $buildDir $dllName),
        (Join-Path $buildDir "$BuildType\$dllName")
    )
    
    $dllPath = $null
    foreach ($path in $dllPaths) {
        if (Test-Path $path) {
            $dllPath = $path
            break
        }
    }
    
    if ($dllPath) {
        Copy-Item -Path $dllPath -Destination $abiOutputDir -Force
        $size = [math]::Round((Get-Item $dllPath).Length / 1MB, 2)
        Write-Info "Built: $abiOutputDir\$dllName (${size}MB)"
    } else {
        Write-Err "Build output not found: $dllName"
        return $false
    }
    
    # Copy zlib1.dll runtime dependency
    $zlibDll = Join-Path $script:VcpkgPath "installed\x64-windows\bin\zlib1.dll"
    if (Test-Path $zlibDll) {
        Copy-Item -Path $zlibDll -Destination $abiOutputDir -Force
        Write-Info "Copied: zlib1.dll"
    } else {
        Write-Warn "zlib1.dll not found - app may fail at runtime"
    }
    
    return $true
}

# Create archive
function New-Archive {
    Write-Step "Creating archive..."
    
    $archivePath = Join-Path $RepoRoot 'build\agus-binaries-windows.zip'
    
    # Remove existing archive
    if (Test-Path $archivePath) {
        Remove-Item -Path $archivePath -Force
    }
    
    # Create zip
    Push-Location (Join-Path $RepoRoot 'build')
    try {
        Compress-Archive -Path 'agus-binaries-windows' -DestinationPath 'agus-binaries-windows.zip' -Force
    } finally {
        Pop-Location
    }
    
    if (Test-Path $archivePath) {
        $size = [math]::Round((Get-Item $archivePath).Length / 1MB, 2)
        Write-Info "Archive created: $archivePath (${size}MB)"
    } else {
        Write-Warn "Failed to create archive"
    }
}

# Print summary
function Write-Summary {
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "Build Complete!" -ForegroundColor Green
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Output directory: $OutputDir" -ForegroundColor White
    Write-Host ""
    Write-Host "Built files:" -ForegroundColor White
    
    $dllPath = Join-Path $OutputDir "x64\agus_maps_flutter.dll"
    if (Test-Path $dllPath) {
        $size = [math]::Round((Get-Item $dllPath).Length / 1MB, 2)
        Write-Host "  - x64/agus_maps_flutter.dll: ${size}MB" -ForegroundColor Green
    } else {
        Write-Host "  - x64/agus_maps_flutter.dll: NOT BUILT" -ForegroundColor Red
    }
    
    $zlibPath = Join-Path $OutputDir "x64\zlib1.dll"
    if (Test-Path $zlibPath) {
        $size = [math]::Round((Get-Item $zlibPath).Length / 1KB, 2)
        Write-Host "  - x64/zlib1.dll: ${size}KB" -ForegroundColor Green
    }
    
    Write-Host ""
    
    if (-not $SkipArchive) {
        $archivePath = Join-Path $RepoRoot 'build\agus-binaries-windows.zip'
        if (Test-Path $archivePath) {
            $size = [math]::Round((Get-Item $archivePath).Length / 1MB, 2)
            Write-Host "Archive: $archivePath (${size}MB)" -ForegroundColor White
        }
    }
    
    Write-Host ""
    Write-Host "To use in CI release, upload the zip to GitHub Releases" -ForegroundColor Yellow
    Write-Host "=========================================" -ForegroundColor Cyan
}

# Main entry point
function Main {
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "CoMaps Windows Native Library Build" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Build type: $BuildType"
    Write-Host "Architecture: x64"
    Write-Host ""
    
    # Setup Visual Studio environment
    if (-not (Initialize-VsEnvironment)) {
        Write-Warn "Visual Studio environment setup failed, continuing anyway..."
    }
    
    # Validate prerequisites
    if (-not (Test-Prerequisites)) {
        exit 1
    }
    
    # Bootstrap dependencies
    Initialize-ComapsDependencies
    
    # Clean output directory
    if (Test-Path $OutputDir) {
        Remove-Item -Path $OutputDir -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
    
    # Build
    if (-not (Build-Windows)) {
        Write-Err "Build failed!"
        exit 1
    }
    
    # Create archive
    if (-not $SkipArchive) {
        New-Archive
    }
    
    # Print summary
    Write-Summary
}

# Run main
Main
