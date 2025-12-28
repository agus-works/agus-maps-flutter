#Requires -Version 7.0
<#
.SYNOPSIS
    Build CoMaps native libraries for Android on Windows.

.DESCRIPTION
    This script compiles the CoMaps native code for Android using the NDK and CMake
    on a Windows workstation. It produces shared libraries (.so) for each supported
    ABI that can be used by the Flutter plugin.

.PARAMETER ABIs
    Space-separated list of ABIs to build. 
    Default: "arm64-v8a armeabi-v7a x86_64"

.PARAMETER BuildType
    Build configuration: Release or Debug.
    Default: Release

.PARAMETER MinSdk
    Minimum Android SDK version.
    Default: 24

.PARAMETER NdkVersion
    Android NDK version to use.
    Default: 27.2.12479018

.PARAMETER AndroidHome
    Path to Android SDK. Auto-detected if not specified.

.PARAMETER Clean
    Clean build directories before building.

.PARAMETER SkipArchive
    Skip creating the zip archive.

.EXAMPLE
    .\scripts\build_binaries_android.ps1

.EXAMPLE
    .\scripts\build_binaries_android.ps1 -ABIs "arm64-v8a" -BuildType Debug -Clean

.EXAMPLE
    .\scripts\build_binaries_android.ps1 -NdkVersion "26.1.10909125" -MinSdk 26

.NOTES
    This is the Windows PowerShell equivalent of scripts/build_binaries_android.sh

    Prerequisites:
    - Android SDK with NDK installed
    - CMake (from Android SDK or system)
    - Ninja build system
    - thirdparty/comaps must exist (run bootstrap_android.ps1 first)
#>

[CmdletBinding()]
param(
    [string]$ABIs = "arm64-v8a armeabi-v7a x86_64",
    [ValidateSet('Release', 'Debug')]
    [string]$BuildType = 'Release',
    [int]$MinSdk = 24,
    [string]$NdkVersion = '27.2.12479018',
    [string]$AndroidHome = '',
    [switch]$Clean,
    [switch]$SkipArchive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$OutputDir = Join-Path $RepoRoot 'build\agus-binaries-android'
$ComapsDir = Join-Path $RepoRoot 'thirdparty\comaps'
$SrcDir = Join-Path $RepoRoot 'src'

# Colors (Windows Terminal/PowerShell 7 support)
function Write-Step { param([string]$Message) Write-Host "[STEP] $Message" -ForegroundColor Blue }
function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Err { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

# Detect Android SDK location
function Find-AndroidSdk {
    # Check explicit parameter
    if ($AndroidHome -and (Test-Path $AndroidHome)) {
        return $AndroidHome
    }
    
    # Check environment variables
    $envVars = @('ANDROID_HOME', 'ANDROID_SDK_ROOT', 'ANDROID_SDK')
    foreach ($var in $envVars) {
        $val = [Environment]::GetEnvironmentVariable($var)
        if ($val -and (Test-Path $val)) {
            return $val
        }
    }
    
    # Common Windows locations
    $commonPaths = @(
        "$env:LOCALAPPDATA\Android\Sdk",
        "$env:USERPROFILE\AppData\Local\Android\Sdk",
        "C:\Android\Sdk",
        "$env:ProgramFiles\Android\android-sdk"
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
    param([string]$SdkPath)
    
    # Try Android SDK CMake first
    $sdkCmakePath = Join-Path $SdkPath "cmake\3.22.1\bin\cmake.exe"
    if (Test-Path $sdkCmakePath) {
        return $sdkCmakePath
    }
    
    # Try any version in SDK
    $cmakeDir = Join-Path $SdkPath 'cmake'
    if (Test-Path $cmakeDir) {
        $versions = Get-ChildItem -Path $cmakeDir -Directory | Sort-Object Name -Descending
        foreach ($ver in $versions) {
            $cmakePath = Join-Path $ver.FullName 'bin\cmake.exe'
            if (Test-Path $cmakePath) {
                return $cmakePath
            }
        }
    }
    
    # Try system CMake
    $systemCmake = Get-Command cmake -ErrorAction SilentlyContinue
    if ($systemCmake) {
        return $systemCmake.Source
    }
    
    return $null
}

# Find Ninja executable
function Find-Ninja {
    param([string]$SdkPath)
    
    # Try Android SDK CMake's ninja first
    $cmakeDir = Join-Path $SdkPath 'cmake'
    if (Test-Path $cmakeDir) {
        $versions = Get-ChildItem -Path $cmakeDir -Directory | Sort-Object Name -Descending
        foreach ($ver in $versions) {
            $ninjaPath = Join-Path $ver.FullName 'bin\ninja.exe'
            if (Test-Path $ninjaPath) {
                return $ninjaPath
            }
        }
    }
    
    # Try system Ninja
    $systemNinja = Get-Command ninja -ErrorAction SilentlyContinue
    if ($systemNinja) {
        return $systemNinja.Source
    }
    
    return $null
}

# Validate prerequisites
function Test-Prerequisites {
    Write-Step "Validating prerequisites..."
    
    # Check CoMaps source
    if (-not (Test-Path $ComapsDir)) {
        Write-Err "CoMaps source not found at: $ComapsDir"
        Write-Err "Run .\scripts\bootstrap_android.ps1 first"
        return $false
    }
    Write-Info "CoMaps source: $ComapsDir"
    
    # Find Android SDK
    $script:AndroidSdkPath = Find-AndroidSdk
    if (-not $script:AndroidSdkPath) {
        Write-Err "Could not detect Android SDK location"
        Write-Err "Please set ANDROID_HOME environment variable or use -AndroidHome parameter"
        return $false
    }
    Write-Info "Android SDK: $script:AndroidSdkPath"
    
    # Find NDK
    $script:NdkPath = Join-Path $script:AndroidSdkPath "ndk\$NdkVersion"
    if (-not (Test-Path $script:NdkPath)) {
        Write-Warn "NDK $NdkVersion not found, searching for alternatives..."
        
        $ndkDir = Join-Path $script:AndroidSdkPath 'ndk'
        if (Test-Path $ndkDir) {
            $ndkVersions = Get-ChildItem -Path $ndkDir -Directory | Sort-Object Name -Descending
            if ($ndkVersions.Count -gt 0) {
                $script:NdkPath = $ndkVersions[0].FullName
                Write-Info "Using NDK: $($ndkVersions[0].Name)"
            }
        }
        
        if (-not (Test-Path $script:NdkPath)) {
            Write-Err "No Android NDK found"
            Write-Err "Install NDK using Android Studio SDK Manager or:"
            Write-Err "  sdkmanager 'ndk;$NdkVersion'"
            return $false
        }
    }
    Write-Info "NDK path: $script:NdkPath"
    
    # Find CMake
    $script:CMakePath = Find-CMake -SdkPath $script:AndroidSdkPath
    if (-not $script:CMakePath) {
        Write-Err "CMake not found"
        Write-Err "Install via Android Studio SDK Manager or system package manager"
        return $false
    }
    Write-Info "CMake: $script:CMakePath"
    
    # Find Ninja
    $script:NinjaPath = Find-Ninja -SdkPath $script:AndroidSdkPath
    if (-not $script:NinjaPath) {
        Write-Warn "Ninja not found, will try to use CMake's default generator"
    } else {
        Write-Info "Ninja: $script:NinjaPath"
    }
    
    return $true
}

# Bootstrap CoMaps dependencies
function Initialize-ComapsDependencies {
    Write-Step "Bootstrapping CoMaps dependencies..."
    
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
        $bootstrapSh = Join-Path $boostDir 'bootstrap.sh'
        
        if (Test-Path $bootstrapBat) {
            & cmd /c $bootstrapBat 2>&1 | Out-Null
            $b2 = Join-Path $boostDir 'b2.exe'
            if (Test-Path $b2) {
                & $b2 headers 2>&1 | Out-Null
            }
        } elseif (Test-Path $bootstrapSh) {
            # Use Git Bash
            $gitBash = "C:\Program Files\Git\bin\bash.exe"
            if (Test-Path $gitBash) {
                $boostDirPosix = $boostDir -replace '\\', '/' -replace '^([A-Za-z]):', '/$1'
                & $gitBash -c "cd '$boostDirPosix' && ./bootstrap.sh && ./b2 headers" 2>&1 | Out-Null
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

# Build for a single ABI
function Build-Abi {
    param([string]$Abi)
    
    $buildDir = Join-Path $RepoRoot "build\android-$Abi"
    $abiOutputDir = Join-Path $OutputDir $Abi
    
    Write-Step "Building for ABI: $Abi"
    
    # Clean build directory if requested
    if ($Clean -and (Test-Path $buildDir)) {
        Write-Info "Cleaning build directory..."
        Remove-Item -Path $buildDir -Recurse -Force
    }
    
    # Create build directory
    New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
    
    # CMake toolchain file
    $toolchainFile = Join-Path $script:NdkPath 'build\cmake\android.toolchain.cmake'
    
    # Configure CMake
    Write-Info "Configuring CMake for $Abi..."
    
    $cmakeArgs = @(
        '-B', $buildDir,
        '-S', $SrcDir,
        "-DCMAKE_TOOLCHAIN_FILE=$toolchainFile",
        "-DANDROID_ABI=$Abi",
        "-DANDROID_PLATFORM=android-$MinSdk",
        "-DANDROID_NDK=$($script:NdkPath)",
        "-DCMAKE_BUILD_TYPE=$BuildType",
        "-DCMAKE_ANDROID_ARCH_ABI=$Abi",
        '-DANDROID=ON'
    )
    
    # Add Ninja generator if available
    if ($script:NinjaPath) {
        $cmakeArgs += @('-G', 'Ninja')
        # Set CMAKE_MAKE_PROGRAM to ninja path
        $cmakeArgs += "-DCMAKE_MAKE_PROGRAM=$($script:NinjaPath)"
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
        Write-Err "CMake configuration failed for $Abi"
        return $false
    }
    
    # Build
    Write-Info "Building $Abi..."
    $buildArgs = @('--build', $buildDir, '--parallel')
    
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
        Write-Err "Build failed for $Abi"
        return $false
    }
    
    # Copy output
    New-Item -ItemType Directory -Force -Path $abiOutputDir | Out-Null
    
    $libName = 'libagus_maps_flutter.so'
    $libPath = Join-Path $buildDir $libName
    
    if (Test-Path $libPath) {
        Copy-Item -Path $libPath -Destination $abiOutputDir -Force
        $size = [math]::Round((Get-Item $libPath).Length / 1MB, 2)
        Write-Info "Built: $abiOutputDir\$libName (${size}MB)"
        return $true
    } else {
        Write-Err "Build output not found: $libPath"
        return $false
    }
}

# Create archive
function New-Archive {
    Write-Step "Creating archive..."
    
    $archivePath = Join-Path $RepoRoot 'build\agus-binaries-android.zip'
    
    # Remove existing archive
    if (Test-Path $archivePath) {
        Remove-Item -Path $archivePath -Force
    }
    
    # Create zip
    Push-Location (Join-Path $RepoRoot 'build')
    try {
        Compress-Archive -Path 'agus-binaries-android' -DestinationPath 'agus-binaries-android.zip' -Force
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
    Write-Host "Built ABIs:" -ForegroundColor White
    
    foreach ($abi in $ABIs.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)) {
        $libPath = Join-Path $OutputDir "$abi\libagus_maps_flutter.so"
        if (Test-Path $libPath) {
            $size = [math]::Round((Get-Item $libPath).Length / 1MB, 2)
            Write-Host "  - $abi`: ${size}MB" -ForegroundColor Green
        } else {
            Write-Host "  - $abi`: NOT BUILT" -ForegroundColor Red
        }
    }
    
    Write-Host ""
    
    if (-not $SkipArchive) {
        $archivePath = Join-Path $RepoRoot 'build\agus-binaries-android.zip'
        if (Test-Path $archivePath) {
            Write-Host "Archive: $archivePath" -ForegroundColor White
        }
    }
    
    Write-Host ""
    Write-Host "To use in CI release, upload the zip to GitHub Releases" -ForegroundColor Yellow
    Write-Host "=========================================" -ForegroundColor Cyan
}

# Main entry point
function Main {
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host "CoMaps Android Native Library Build" -ForegroundColor Cyan
    Write-Host "(Windows PowerShell Edition)" -ForegroundColor Cyan
    Write-Host "=========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Build type: $BuildType"
    Write-Host "ABIs: $ABIs"
    Write-Host "Min SDK: $MinSdk"
    Write-Host ""
    
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
    
    # Build each ABI
    $abiList = $ABIs.Split(' ', [StringSplitOptions]::RemoveEmptyEntries)
    $successCount = 0
    
    foreach ($abi in $abiList) {
        if (Build-Abi -Abi $abi) {
            $successCount++
        }
    }
    
    if ($successCount -eq 0) {
        Write-Err "All builds failed!"
        exit 1
    }
    
    if ($successCount -lt $abiList.Count) {
        Write-Warn "Some builds failed ($successCount/$($abiList.Count) succeeded)"
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
