#Requires -Version 7.0
<#
.SYNOPSIS
    Bootstraps the Windows development environment for agus-maps-flutter.

.DESCRIPTION
    This script:
    1. Installs vcpkg if not present
    2. Installs required dependencies (zlib)
    3. Sets up environment variables

.PARAMETER VcpkgRoot
    Path where vcpkg should be installed. Defaults to C:\vcpkg

.EXAMPLE
    .\scripts\bootstrap_windows.ps1

.EXAMPLE
    .\scripts\bootstrap_windows.ps1 -VcpkgRoot D:\tools\vcpkg
#>

param(
    [string]$VcpkgRoot = "C:\vcpkg"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

Write-Host "=== Agus Maps Flutter - Windows Bootstrap ===" -ForegroundColor Cyan
Write-Host "Repository Root: $RepoRoot"
Write-Host "vcpkg Root: $VcpkgRoot"
Write-Host ""

# ============================================================================
# Step 1: Install vcpkg
# ============================================================================
Write-Host "=== Step 1: Setting up vcpkg ===" -ForegroundColor Yellow

$vcpkgExe = Join-Path $VcpkgRoot "vcpkg.exe"

if (Test-Path $vcpkgExe) {
    Write-Host "vcpkg already installed at: $VcpkgRoot" -ForegroundColor Green
} else {
    Write-Host "Installing vcpkg..." -ForegroundColor Yellow
    
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
    
    Write-Host "vcpkg installed successfully" -ForegroundColor Green
}

# ============================================================================
# Step 2: Install dependencies
# ============================================================================
Write-Host ""
Write-Host "=== Step 2: Installing dependencies ===" -ForegroundColor Yellow

# Install zlib for x64-windows
Write-Host "Installing zlib:x64-windows..."
& $vcpkgExe install zlib:x64-windows
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to install zlib"
    exit 1
}

Write-Host "Dependencies installed successfully" -ForegroundColor Green

# ============================================================================
# Step 3: Set environment variables
# ============================================================================
Write-Host ""
Write-Host "=== Step 3: Setting environment variables ===" -ForegroundColor Yellow

# Set VCPKG_ROOT for current session
$env:VCPKG_ROOT = $VcpkgRoot
Write-Host "Set VCPKG_ROOT=$VcpkgRoot (current session)" -ForegroundColor Green

# Offer to set permanently
$setPermanent = Read-Host "Set VCPKG_ROOT permanently for current user? (y/n)"
if ($setPermanent -eq 'y' -or $setPermanent -eq 'Y') {
    [System.Environment]::SetEnvironmentVariable('VCPKG_ROOT', $VcpkgRoot, [System.EnvironmentVariableTarget]::User)
    Write-Host "VCPKG_ROOT set permanently for current user" -ForegroundColor Green
}

# ============================================================================
# Step 4: Fetch CoMaps and apply patches
# ============================================================================
Write-Host ""
Write-Host "=== Step 4: Setting up CoMaps ===" -ForegroundColor Yellow

$fetchScript = Join-Path $ScriptDir "fetch_comaps.ps1"
if (Test-Path $fetchScript) {
    & $fetchScript
} else {
    Write-Warning "fetch_comaps.ps1 not found, skipping CoMaps setup"
}

Write-Host ""
Write-Host "=== Step 5: Copy CoMaps data into example assets ===" -ForegroundColor Yellow

$copyDataPs1 = Join-Path $ScriptDir "copy_comaps_data.ps1"
if (Test-Path $copyDataPs1) {
    & $copyDataPs1
} else {
    Write-Warning "copy_comaps_data.ps1 not found. You can run scripts/copy_comaps_data.sh in bash instead."
}

# ============================================================================
# Done
# ============================================================================
Write-Host ""
Write-Host "=== Bootstrap Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "To build the plugin, run:" -ForegroundColor Gray
Write-Host "  cd example" -ForegroundColor White
Write-Host "  flutter build windows" -ForegroundColor White
Write-Host ""
Write-Host "Make sure VCPKG_ROOT is set in your shell:" -ForegroundColor Gray
Write-Host "  `$env:VCPKG_ROOT = '$VcpkgRoot'" -ForegroundColor White
Write-Host ""
