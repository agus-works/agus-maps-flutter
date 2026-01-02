#Requires -Version 7.0
<#
.SYNOPSIS
    Unified Bootstrap for Windows Development

.DESCRIPTION
    This script sets up the complete development environment for agus_maps_flutter
    on Windows. It prepares ALL target platforms that can be built from Windows:
      - Android (arm64-v8a, armeabi-v7a, x86_64)
      - Windows (x64)

    What it does:
      1. Fetch CoMaps source code (or restore from local cache)
      2. Create cache archive after fresh clone (before patches)
      3. Apply patches (superset for all platforms)
      4. Build Boost headers
      5. Copy CoMaps data files to example assets
      6. Copy Android-specific assets (fonts)
      7. Install vcpkg if not present
      8. Install vcpkg dependencies (zlib)
      9. Set environment variables

    Local Cache Mechanism (development only):
      - After fresh clone, thirdparty is compressed to .thirdparty.7z using 7-Zip
      - Cache is created BEFORE patches are applied (pristine state)
      - If thirdparty is deleted and cache exists, it will be extracted
      - This allows iterating on patches without re-cloning from git
      - Use -NoCache to disable caching behavior

.PARAMETER VcpkgRoot
    Path where vcpkg should be installed. Defaults to C:\vcpkg

.PARAMETER SkipPatches
    Skip applying patches (useful for debugging).

.PARAMETER NoCache
    Disable the 7z caching mechanism. Will not create or use cache.

.PARAMETER Force
    Force re-bootstrap even if already done.

.EXAMPLE
    .\scripts\bootstrap.ps1

.EXAMPLE
    .\scripts\bootstrap.ps1 -VcpkgRoot D:\tools\vcpkg

.EXAMPLE
    .\scripts\bootstrap.ps1 -NoCache

.NOTES
    For macOS/Linux development, use bootstrap.sh instead.
    Linux is not yet supported - see docs/CONTRIBUTING.md for details.
#>

param(
    [string]$VcpkgRoot = "C:\vcpkg",
    [switch]$SkipPatches,
    [switch]$NoCache,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

# Import common bootstrap module
Import-Module (Join-Path $ScriptDir 'BootstrapCommon.psm1') -Force

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Agus Maps Flutter - Unified Bootstrap" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Build Machine: Windows $([System.Environment]::OSVersion.Version)" -ForegroundColor Gray
Write-Host "Target Platforms: Android, Windows" -ForegroundColor Gray
Write-Host "Repository Root: $RepoRoot" -ForegroundColor Gray
Write-Host "vcpkg Root: $VcpkgRoot" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# Step 1: Bootstrap CoMaps (shared with all platforms)
# ============================================================================
Write-LogHeader "Step 1: Bootstrapping CoMaps and Dependencies"

# Show cache status
if ($NoCache) {
    Write-LogInfo "Cache disabled by -NoCache flag"
} elseif (Test-7ZipAvailable) {
    if (Test-ThirdPartyArchive -RepoRoot $RepoRoot) {
        $archivePath = Join-Path $RepoRoot '.thirdparty.7z'
        $sizeMB = [math]::Round((Get-Item $archivePath).Length / 1MB, 2)
        Write-LogInfo "Cache archive found: .thirdparty.7z ($sizeMB MB)"
    } else {
        Write-LogInfo "No cache archive found - will create after fresh clone"
    }
} else {
    Write-LogWarn "7-Zip not found at C:\Program Files\7-Zip\7z.exe - caching disabled"
}

# Run full bootstrap for all platforms
if ($SkipPatches) {
    $env:SKIP_PATCHES = "true"
}

if ($NoCache) {
    Bootstrap-Full -RepoRoot $RepoRoot -Platform 'all' -NoCache
} else {
    Bootstrap-Full -RepoRoot $RepoRoot -Platform 'all'
}

# ============================================================================
# Step 2: Install vcpkg (Windows-specific)
# ============================================================================
Write-Host ""
Write-LogHeader "Step 2: Setting up vcpkg"

$vcpkgExe = Join-Path $VcpkgRoot "vcpkg.exe"

if (Test-Path $vcpkgExe) {
    Write-LogInfo "vcpkg already installed at: $VcpkgRoot"
} else {
    Write-LogInfo "Installing vcpkg..."
    
    # Clone vcpkg
    if (Test-Path $VcpkgRoot) {
        Write-Host "Removing existing incomplete vcpkg installation..."
        Remove-Item -Recurse -Force $VcpkgRoot
    }
    
    git clone https://github.com/Microsoft/vcpkg.git $VcpkgRoot
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to clone vcpkg"
        exit 1
    }
    
    # Bootstrap vcpkg
    Push-Location $VcpkgRoot
    try {
        & .\bootstrap-vcpkg.bat
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to bootstrap vcpkg"
            exit 1
        }
    } finally {
        Pop-Location
    }
    
    Write-LogInfo "vcpkg installed successfully"
}

# ============================================================================
# Step 3: Install vcpkg dependencies
# ============================================================================
Write-Host ""
Write-LogHeader "Step 3: Installing vcpkg dependencies"

# vcpkg.json exists in the repo, so vcpkg will run in manifest mode.
$manifestPath = Join-Path $RepoRoot "vcpkg.json"
if (Test-Path $manifestPath) {
    Write-LogInfo "Installing dependencies from manifest (x64-windows)..."
    Push-Location $RepoRoot
    try {
        & $vcpkgExe install --triplet x64-windows
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to install vcpkg dependencies from manifest"
            exit 1
        }
    } finally {
        Pop-Location
    }
} else {
    # Fallback for classic mode
    Write-LogInfo "Installing zlib:x64-windows (classic mode)..."
    & $vcpkgExe install zlib:x64-windows
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to install zlib"
        exit 1
    }
}

Write-LogInfo "Dependencies installed successfully"

# ============================================================================
# Step 4: Set environment variables
# ============================================================================
Write-Host ""
Write-LogHeader "Step 4: Setting environment variables"

# Set VCPKG_ROOT for current session
$env:VCPKG_ROOT = $VcpkgRoot
Write-LogInfo "Set VCPKG_ROOT=$VcpkgRoot (current session)"

# Check if running interactively
$isInteractive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected

if ($isInteractive) {
    $setPermanent = Read-Host "Set VCPKG_ROOT permanently for current user? (y/n)"
    if ($setPermanent -eq 'y' -or $setPermanent -eq 'Y') {
        [System.Environment]::SetEnvironmentVariable('VCPKG_ROOT', $VcpkgRoot, [System.EnvironmentVariableTarget]::User)
        Write-LogInfo "VCPKG_ROOT set permanently for current user"
    }
} else {
    Write-LogInfo "Non-interactive mode, skipping permanent environment variable setup"
}

# ============================================================================
# Done
# ============================================================================
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Bootstrap Complete!" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This bootstrap has prepared:" -ForegroundColor Gray
Write-Host "  ✓ CoMaps source code and patches" -ForegroundColor Green
Write-Host "  ✓ Boost headers" -ForegroundColor Green
Write-Host "  ✓ CoMaps data files" -ForegroundColor Green
Write-Host "  ✓ Android assets (fonts)" -ForegroundColor Green
Write-Host "  ✓ vcpkg and dependencies" -ForegroundColor Green

# Show cache status
if (-not $NoCache -and (Test-7ZipAvailable)) {
    if (Test-ThirdPartyArchive -RepoRoot $RepoRoot) {
        $archivePath = Join-Path $RepoRoot '.thirdparty.7z'
        $sizeMB = [math]::Round((Get-Item $archivePath).Length / 1MB, 2)
        Write-Host "  ✓ Local cache: .thirdparty.7z ($sizeMB MB)" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Gray
Write-Host ""
Write-Host "  Android:" -ForegroundColor White
Write-Host "    cd example" -ForegroundColor DarkGray
Write-Host "    flutter run -d <android-device>" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Windows:" -ForegroundColor White
Write-Host "    cd example" -ForegroundColor DarkGray
Write-Host "    flutter run -d windows" -ForegroundColor DarkGray
Write-Host ""
Write-Host "To build native libraries from source:" -ForegroundColor Gray
Write-Host "    .\scripts\build_binaries_android.ps1" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Make sure VCPKG_ROOT is set in your shell:" -ForegroundColor Gray
Write-Host "    `$env:VCPKG_ROOT = '$VcpkgRoot'" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Cache tips:" -ForegroundColor Gray
Write-Host "  - Delete 'thirdparty' folder and re-run bootstrap to use cache" -ForegroundColor DarkGray
Write-Host "  - Use -NoCache flag to force fresh clone" -ForegroundColor DarkGray
Write-Host ""
