#Requires -Version 7.0
<#
.SYNOPSIS
    Bootstraps the Windows development environment for agus-maps-flutter.

.DESCRIPTION
    This script sets up everything needed to build the Windows target of
    agus_maps_flutter. It performs:
    
    1. Fetches CoMaps source code
    2. Applies patches (superset for all platforms)
    3. Builds Boost headers
    4. Copies CoMaps data files
    5. Installs vcpkg if not present
    6. Installs required vcpkg dependencies (zlib)
    7. Sets up environment variables

    Note: This bootstrap also prepares dependencies needed for Android builds
    on Windows, ensuring you can build both Windows and Android targets.

.PARAMETER VcpkgRoot
    Path where vcpkg should be installed. Defaults to C:\vcpkg

.PARAMETER SkipPatches
    Skip applying patches (useful for debugging).

.PARAMETER Force
    Force re-bootstrap even if already done.

.EXAMPLE
    .\scripts\bootstrap_windows.ps1

.EXAMPLE
    .\scripts\bootstrap_windows.ps1 -VcpkgRoot D:\tools\vcpkg
#>

param(
    [string]$VcpkgRoot = "C:\vcpkg",
    [switch]$SkipPatches,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

# Import common bootstrap module
Import-Module (Join-Path $ScriptDir 'BootstrapCommon.psm1') -Force

Write-Host "=== Agus Maps Flutter - Windows Bootstrap ===" -ForegroundColor Cyan
Write-Host "Repository Root: $RepoRoot"
Write-Host "vcpkg Root: $VcpkgRoot"
Write-Host ""

# ============================================================================
# Step 1: Bootstrap CoMaps (shared with all platforms)
# ============================================================================
Write-LogHeader "Step 1: Bootstrapping CoMaps and Dependencies"

if ($SkipPatches) {
    Bootstrap-CoMaps -RepoRoot $RepoRoot
    Bootstrap-Boost -RepoRoot $RepoRoot
    Bootstrap-Data -RepoRoot $RepoRoot
} else {
    Bootstrap-Full -RepoRoot $RepoRoot -Platform 'windows'
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
Write-Host "=== Bootstrap Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "This bootstrap has prepared:" -ForegroundColor Gray
Write-Host "  ✓ CoMaps source code and patches" -ForegroundColor Green
Write-Host "  ✓ Boost headers" -ForegroundColor Green
Write-Host "  ✓ CoMaps data files" -ForegroundColor Green
Write-Host "  ✓ vcpkg and dependencies" -ForegroundColor Green
Write-Host ""
Write-Host "You can now build for:" -ForegroundColor Gray
Write-Host "  - Windows:  flutter build windows" -ForegroundColor White
Write-Host "  - Android:  flutter build apk" -ForegroundColor White
Write-Host ""
Write-Host "To build the plugin, run:" -ForegroundColor Gray
Write-Host "  cd example" -ForegroundColor White
Write-Host "  flutter build windows" -ForegroundColor White
Write-Host ""
Write-Host "Make sure VCPKG_ROOT is set in your shell:" -ForegroundColor Gray
Write-Host "  `$env:VCPKG_ROOT = '$VcpkgRoot'" -ForegroundColor White
Write-Host ""
