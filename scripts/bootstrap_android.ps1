#Requires -Version 7.0
<#
.SYNOPSIS
    Bootstrap Android dependencies on Windows.

.DESCRIPTION
    This script prepares the development environment for building the Android
    version of agus_maps_flutter on a Windows workstation.

    What it does:
    - Ensures ./thirdparty/comaps is present (via fetch_comaps.ps1)
    - Applies patches from ./patches/comaps (via apply_comaps_patches.ps1)
    - Prepares boost headers
    - Copies assets (fonts) to example app

.PARAMETER ComapsTag
    Git tag/commit to checkout. Defaults to v2025.12.11-2.

.PARAMETER SkipPatches
    Skip applying patches (useful for debugging).

.PARAMETER Force
    Force re-bootstrap even if already done.

.EXAMPLE
    .\scripts\bootstrap_android.ps1

.EXAMPLE
    .\scripts\bootstrap_android.ps1 -ComapsTag v2025.12.11-2 -Force

.NOTES
    This is the Windows PowerShell equivalent of scripts/bootstrap_android.sh
#>

[CmdletBinding()]
param(
    [string]$ComapsTag = 'v2025.12.11-2',
    [switch]$SkipPatches,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$ThirdpartyDir = Join-Path $RepoRoot 'thirdparty'
$ComapsDir = Join-Path $ThirdpartyDir 'comaps'

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Bootstrap Android Dependencies (Windows)" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Repository Root: $RepoRoot"
Write-Host "CoMaps Tag: $ComapsTag"
Write-Host ""

# Step 1: Fetch CoMaps
Write-Host "[Step 1/4] Fetching CoMaps..." -ForegroundColor Green
$fetchScript = Join-Path $ScriptDir 'fetch_comaps.ps1'
if (Test-Path $fetchScript) {
    & $fetchScript
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
        Write-Error "Failed to fetch CoMaps"
        exit 1
    }
} else {
    Write-Error "fetch_comaps.ps1 not found at: $fetchScript"
    exit 1
}

# Step 2: Apply patches
if (-not $SkipPatches) {
    Write-Host ""
    Write-Host "[Step 2/4] Applying patches..." -ForegroundColor Green
    $applyPatchesScript = Join-Path $ScriptDir 'apply_comaps_patches.ps1'
    if (Test-Path $applyPatchesScript) {
        & $applyPatchesScript
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            Write-Warning "Patch application had issues (may be non-fatal if already applied)"
        }
    } else {
        Write-Warning "apply_comaps_patches.ps1 not found, skipping patches"
    }
} else {
    Write-Host ""
    Write-Host "[Step 2/4] Skipping patches (--SkipPatches specified)" -ForegroundColor Yellow
}

# Step 3: Prepare boost headers
Write-Host ""
Write-Host "[Step 3/4] Preparing boost headers..." -ForegroundColor Green
$boostDir = Join-Path $ComapsDir '3party\boost'
$boostHeadersDir = Join-Path $boostDir 'boost'

if (Test-Path $boostHeadersDir) {
    if (-not $Force) {
        Write-Host "  Boost headers already exist at: $boostHeadersDir" -ForegroundColor Gray
        Write-Host "  Skipping boost build (use -Force to rebuild)" -ForegroundColor Gray
    } else {
        Write-Host "  Force rebuilding boost headers..." -ForegroundColor Yellow
        Remove-Item -Path $boostHeadersDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not (Test-Path $boostHeadersDir) -or $Force) {
    Push-Location $boostDir
    try {
        # Check for bootstrap script
        $bootstrapScript = Join-Path $boostDir 'bootstrap.bat'
        $bootstrapSh = Join-Path $boostDir 'bootstrap.sh'
        
        if (Test-Path $bootstrapScript) {
            Write-Host "  Running bootstrap.bat..." -ForegroundColor Gray
            & cmd /c $bootstrapScript 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            
            $b2Exe = Join-Path $boostDir 'b2.exe'
            if (Test-Path $b2Exe) {
                Write-Host "  Running b2 headers..." -ForegroundColor Gray
                & $b2Exe headers 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            }
        } elseif (Test-Path $bootstrapSh) {
            # Try using Git Bash or WSL
            Write-Host "  No bootstrap.bat found, trying bash..." -ForegroundColor Yellow
            
            $gitBash = "C:\Program Files\Git\bin\bash.exe"
            if (Test-Path $gitBash) {
                Write-Host "  Using Git Bash to run bootstrap.sh..." -ForegroundColor Gray
                $boostDirPosix = $boostDir -replace '\\', '/' -replace '^([A-Za-z]):', '/$1'
                & $gitBash -c "cd '$boostDirPosix' && ./bootstrap.sh && ./b2 headers" 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
            } else {
                Write-Warning "  Neither bootstrap.bat nor Git Bash found"
                Write-Warning "  Boost headers may not be built. Build may still work if headers exist."
            }
        } else {
            Write-Warning "  No bootstrap script found in boost directory"
            Write-Warning "  Boost headers may need to be built manually"
        }
    } finally {
        Pop-Location
    }
}

# Verify boost headers
if (Test-Path $boostHeadersDir) {
    Write-Host "  ✓ Boost headers ready" -ForegroundColor Green
} else {
    Write-Warning "  Boost headers directory not found - build may fail"
}

# Step 4: Copy assets (fonts)
Write-Host ""
Write-Host "[Step 4/4] Copying assets (fonts)..." -ForegroundColor Green
$fontsSource = Join-Path $ComapsDir 'data\fonts'
$fontsDestDir = Join-Path $RepoRoot 'example\android\app\src\main\assets'
$fontsDest = Join-Path $fontsDestDir 'fonts'

if (Test-Path $fontsSource) {
    New-Item -ItemType Directory -Force -Path $fontsDestDir | Out-Null
    
    if (Test-Path $fontsDest) {
        Remove-Item -Path $fontsDest -Recurse -Force
    }
    
    Copy-Item -Path $fontsSource -Destination $fontsDest -Recurse -Force
    $fontCount = (Get-ChildItem -Path $fontsDest -Filter '*.ttf' -Recurse).Count
    Write-Host "  ✓ Copied $fontCount font files to: $fontsDest" -ForegroundColor Green
} else {
    Write-Warning "  Fonts directory not found at: $fontsSource"
}

# Summary
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Bootstrap Complete!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Copy CoMaps data files:"
Write-Host "     .\scripts\copy_comaps_data.ps1" -ForegroundColor White
Write-Host ""
Write-Host "  2. Build and run the example app:"
Write-Host "     cd example" -ForegroundColor White
Write-Host "     flutter run" -ForegroundColor White
Write-Host ""
Write-Host "  3. Or build Android binaries:"
Write-Host "     .\scripts\build_binaries_android.ps1" -ForegroundColor White
Write-Host ""
