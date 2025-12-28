#Requires -Version 7.0
<#
.SYNOPSIS
    Common bootstrap functions for Windows PowerShell 7+

.DESCRIPTION
    This module provides shared functions for bootstrapping the agus_maps_flutter
    development environment on Windows. All platform-specific bootstrap scripts
    should import this module.

.NOTES
    Requires PowerShell 7.0 or later for cross-platform compatibility.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# Configuration
# ============================================================================

$script:COMAPS_TAG_DEFAULT = 'v2025.12.11-2'
$script:COMAPS_TAG = if ($env:COMAPS_TAG) { $env:COMAPS_TAG } else { $script:COMAPS_TAG_DEFAULT }
$script:COMAPS_GIT_URL = 'https://github.com/comaps/comaps.git'

# ============================================================================
# Logging Functions
# ============================================================================

function Write-LogInfo {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Write-LogWarn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-LogError {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-LogHeader {
    param([string]$Message)
    Write-Host "=== $Message ===" -ForegroundColor Cyan
}

# ============================================================================
# Bootstrap-CoMaps - Fetch CoMaps source and initialize submodules
# ============================================================================

function Bootstrap-CoMaps {
    [CmdletBinding()]
    param(
        [string]$RepoRoot,
        [string]$Tag = $script:COMAPS_TAG
    )

    Write-LogHeader "Bootstrapping CoMaps"
    
    $thirdpartyDir = Join-Path $RepoRoot 'thirdparty'
    $comapsDir = Join-Path $thirdpartyDir 'comaps'
    
    # Create thirdparty directory if needed
    if (-not (Test-Path $thirdpartyDir)) {
        New-Item -ItemType Directory -Path $thirdpartyDir -Force | Out-Null
        Write-LogInfo "Created thirdparty directory"
    }
    
    # Clone or update repository
    if (Test-Path (Join-Path $comapsDir '.git')) {
        Write-LogInfo "CoMaps repository already exists, fetching tags..."
        
        Push-Location $comapsDir
        try {
            & git fetch --tags --prune 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
            
            Write-LogInfo "Checking out tag: $Tag"
            & git checkout --detach $Tag 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
            
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to checkout tag: $Tag"
            }
        } finally {
            Pop-Location
        }
    } else {
        Write-LogInfo "Cloning CoMaps repository..."
        
        # Remove directory if it exists but isn't a git repo
        if (Test-Path $comapsDir) {
            Remove-Item -Path $comapsDir -Recurse -Force
        }
        
        # Clone without checkout to configure git settings first
        $cloneArgs = @('clone', '--no-checkout', '--branch', $Tag, $script:COMAPS_GIT_URL, $comapsDir)
        & git @cloneArgs 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
        
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to clone CoMaps repository"
        }
        
        # Configure git settings before checkout
        Push-Location $comapsDir
        try {
            & git config core.autocrlf false
            & git config core.eol lf
            & git checkout HEAD 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
        } finally {
            Pop-Location
        }
        
        Write-LogInfo "Cloned successfully"
    }
    
    # Initialize ALL submodules recursively - critical for patches
    Write-LogInfo "Initializing submodules (this may take a while)..."
    Push-Location $comapsDir
    try {
        & git submodule update --init --recursive 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
        if ($LASTEXITCODE -ne 0) {
            Write-LogWarn "Submodule initialization had issues (may be non-fatal)"
        }
        
        $commit = git rev-parse --short HEAD 2>&1
        $describe = git describe --tags --always 2>&1
        Write-LogInfo "At commit: $commit ($describe)"
    } finally {
        Pop-Location
    }
    
    Write-LogInfo "CoMaps bootstrap complete"
}

# ============================================================================
# Bootstrap-ApplyPatches - Apply patches to CoMaps checkout
# ============================================================================

function Bootstrap-ApplyPatches {
    [CmdletBinding()]
    param(
        [string]$RepoRoot,
        [switch]$DryRun,
        [switch]$NoReset
    )

    Write-LogHeader "Applying CoMaps Patches"
    
    $comapsDir = Join-Path $RepoRoot 'thirdparty' 'comaps'
    $patchesDir = Join-Path $RepoRoot 'patches' 'comaps'
    
    if (-not (Test-Path $comapsDir)) {
        throw "CoMaps directory not found: $comapsDir"
    }
    
    if (-not (Test-Path $patchesDir)) {
        Write-LogWarn "Patches directory not found: $patchesDir"
        return
    }
    
    # Get all patch files in sorted order
    $patchFiles = Get-ChildItem -Path $patchesDir -Filter "*.patch" -ErrorAction SilentlyContinue |
                  Sort-Object Name
    
    if ($patchFiles.Count -eq 0) {
        Write-LogWarn "No patch files found"
        return
    }
    
    Write-LogInfo "Found $($patchFiles.Count) patch file(s) to apply"
    
    Push-Location $comapsDir
    try {
        # Reset working tree before applying patches
        if (-not $NoReset -and -not $DryRun) {
            Write-LogInfo "Resetting working tree to HEAD..."
            & git checkout --force HEAD 2>&1 | Out-Null
            & git clean -fd 2>&1 | Out-Null
            
            # Reset submodules
            Write-LogInfo "Resetting submodules..."
            & git submodule foreach --recursive 'git checkout --force HEAD 2>/dev/null || true' 2>&1 | Out-Null
            & git submodule foreach --recursive 'git clean -fd 2>/dev/null || true' 2>&1 | Out-Null
        }
        
        $applied = 0
        $skipped = 0
        $failed = 0
        
        foreach ($patchFile in $patchFiles) {
            $patchPath = $patchFile.FullName
            $patchName = $patchFile.Name
            
            # Extract target file from patch
            $targetFile = $null
            $firstLine = Get-Content $patchPath -TotalCount 1
            if ($firstLine -match 'diff --git a/(.+?) b/') {
                $targetFile = $Matches[1]
            }
            
            # Check if target file exists (skip patches for uninitialized submodules)
            if ($targetFile -and -not (Test-Path $targetFile)) {
                Write-LogWarn "Skipping $patchName (target '$targetFile' does not exist)"
                $skipped++
                continue
            }
            
            Write-LogInfo "Applying $patchName"
            
            if ($DryRun) {
                $checkResult = & git apply --check $patchPath 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  [DRY RUN] Would apply successfully" -ForegroundColor Green
                    $applied++
                } else {
                    Write-Host "  [DRY RUN] Would fail or already applied" -ForegroundColor Yellow
                    $skipped++
                }
                continue
            }
            
            # Try direct apply first
            $applyResult = & git apply --whitespace=nowarn $patchPath 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Applied successfully" -ForegroundColor Green
                $applied++
            } else {
                # Try 3-way merge
                $apply3Result = & git apply --3way --whitespace=nowarn $patchPath 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  Applied successfully (3-way merge)" -ForegroundColor Green
                    $applied++
                } else {
                    # Check if already applied
                    $reverseResult = & git apply --check --reverse $patchPath 2>&1
                    
                    if ($LASTEXITCODE -eq 0) {
                        Write-Host "  Already applied (skipping)" -ForegroundColor Yellow
                        $skipped++
                    } else {
                        Write-Host "  Failed to apply" -ForegroundColor Red
                        $failed++
                    }
                }
            }
        }
        
        Write-Host ""
        Write-LogInfo "Patch summary: Applied=$applied, Skipped=$skipped, Failed=$failed"
        
        if ($failed -gt 0) {
            Write-LogWarn "Some patches failed. Build may still succeed if patches were optional."
        }
        
    } finally {
        Pop-Location
    }
}

# ============================================================================
# Bootstrap-Boost - Build Boost headers
# ============================================================================

function Bootstrap-Boost {
    [CmdletBinding()]
    param(
        [string]$RepoRoot,
        [switch]$Force
    )

    Write-LogHeader "Building Boost Headers"
    
    $boostDir = Join-Path $RepoRoot 'thirdparty' 'comaps' '3party' 'boost'
    $boostHeaders = Join-Path $boostDir 'boost'
    
    if ((Test-Path $boostHeaders) -and -not $Force) {
        Write-LogInfo "Boost headers already exist"
        return
    }
    
    if (-not (Test-Path $boostDir)) {
        throw "Boost directory not found at $boostDir"
    }
    
    Push-Location $boostDir
    try {
        $bootstrapBat = Join-Path $boostDir 'bootstrap.bat'
        $bootstrapSh = Join-Path $boostDir 'bootstrap.sh'
        
        if (Test-Path $bootstrapBat) {
            Write-LogInfo "Running bootstrap.bat..."
            & cmd /c $bootstrapBat 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
            
            $b2Exe = Join-Path $boostDir 'b2.exe'
            if (Test-Path $b2Exe) {
                Write-LogInfo "Running b2 headers..."
                & $b2Exe headers 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
            }
        } elseif (Test-Path $bootstrapSh) {
            # Try using Git Bash
            $gitBash = "C:\Program Files\Git\bin\bash.exe"
            if (Test-Path $gitBash) {
                Write-LogInfo "Using Git Bash to run bootstrap.sh..."
                $boostDirPosix = $boostDir -replace '\\', '/' -replace '^([A-Za-z]):', '/$1'
                & $gitBash -c "cd '$boostDirPosix' && ./bootstrap.sh && ./b2 headers" 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
            } else {
                Write-LogWarn "Neither bootstrap.bat nor Git Bash found"
            }
        } else {
            Write-LogWarn "No bootstrap script found in boost directory"
        }
    } finally {
        Pop-Location
    }
    
    if (Test-Path $boostHeaders) {
        Write-LogInfo "Boost headers built successfully"
    } else {
        Write-LogWarn "Boost headers directory not found - build may fail"
    }
}

# ============================================================================
# Bootstrap-Data - Copy CoMaps data files to example assets
# ============================================================================

function Bootstrap-Data {
    [CmdletBinding()]
    param(
        [string]$RepoRoot
    )

    Write-LogHeader "Copying CoMaps Data Files"
    
    $comapsData = Join-Path $RepoRoot 'thirdparty' 'comaps' 'data'
    $destData = Join-Path $RepoRoot 'example' 'assets' 'comaps_data'
    
    if (-not (Test-Path $comapsData)) {
        Write-LogWarn "CoMaps data directory not found at $comapsData"
        return
    }
    
    New-Item -ItemType Directory -Force -Path $destData | Out-Null
    
    # Essential files
    $essentialFiles = @(
        "classificator.txt",
        "types.txt",
        "categories.txt",
        "visibility.txt",
        "countries.txt",
        "countries_meta.txt",
        "packed_polygons.bin",
        "drules_proto.bin",
        "drules_proto_default_light.bin",
        "drules_proto_default_dark.bin",
        "drules_proto_outdoors_light.bin",
        "drules_proto_outdoors_dark.bin",
        "drules_proto_vehicle_light.bin",
        "drules_proto_vehicle_dark.bin",
        "drules_hash",
        "transit_colors.txt",
        "colors.txt",
        "patterns.txt",
        "editor.config"
    )
    
    foreach ($file in $essentialFiles) {
        $src = Join-Path $comapsData $file
        if (Test-Path $src) {
            Copy-Item -Force -Path $src -Destination (Join-Path $destData $file)
            Write-Host "  ✓ $file" -ForegroundColor Green
        } else {
            Write-Host "  ✗ $file (not found)" -ForegroundColor Yellow
        }
    }
    
    # Directories
    $dirsToCopy = @("categories-strings", "countries-strings", "fonts", "symbols", "styles")
    
    foreach ($dir in $dirsToCopy) {
        $srcDir = Join-Path $comapsData $dir
        $dstDir = Join-Path $destData $dir
        if (Test-Path $srcDir) {
            New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
            Copy-Item -Force -Recurse -Path (Join-Path $srcDir '*') -Destination $dstDir
            Write-Host "  ✓ $dir/" -ForegroundColor Green
        }
    }
    
    Write-LogInfo "Data files copied to: $destData"
}

# ============================================================================
# Bootstrap-AndroidAssets - Copy fonts to Android assets
# ============================================================================

function Bootstrap-AndroidAssets {
    [CmdletBinding()]
    param(
        [string]$RepoRoot
    )

    Write-LogHeader "Copying Android Assets"
    
    $fontsSource = Join-Path $RepoRoot 'thirdparty' 'comaps' 'data' 'fonts'
    $fontsDestDir = Join-Path $RepoRoot 'example' 'android' 'app' 'src' 'main' 'assets'
    $fontsDest = Join-Path $fontsDestDir 'fonts'
    
    if (Test-Path $fontsSource) {
        New-Item -ItemType Directory -Force -Path $fontsDestDir | Out-Null
        
        if (Test-Path $fontsDest) {
            Remove-Item -Path $fontsDest -Recurse -Force
        }
        
        Copy-Item -Path $fontsSource -Destination $fontsDest -Recurse -Force
        $fontCount = (Get-ChildItem -Path $fontsDest -Filter '*.ttf' -Recurse -ErrorAction SilentlyContinue).Count
        Write-LogInfo "Copied $fontCount font files to Android assets"
    } else {
        Write-LogWarn "Fonts directory not found at $fontsSource"
    }
}

# ============================================================================
# Bootstrap-Full - Run full bootstrap for specified platform
# ============================================================================

function Bootstrap-Full {
    [CmdletBinding()]
    param(
        [string]$RepoRoot,
        [ValidateSet('all', 'windows', 'android')]
        [string]$Platform = 'all'
    )

    Write-LogHeader "Full Bootstrap for agus_maps_flutter"
    Write-LogInfo "Platform: $Platform"
    Write-LogInfo "CoMaps tag: $script:COMAPS_TAG"
    
    # Step 1: Fetch CoMaps and initialize submodules
    Bootstrap-CoMaps -RepoRoot $RepoRoot
    
    # Step 2: Apply patches (superset for all platforms)
    Bootstrap-ApplyPatches -RepoRoot $RepoRoot
    
    # Step 3: Build Boost headers
    Bootstrap-Boost -RepoRoot $RepoRoot
    
    # Step 4: Copy data files
    Bootstrap-Data -RepoRoot $RepoRoot
    
    # Platform-specific steps
    if ($Platform -eq 'android' -or $Platform -eq 'all') {
        Bootstrap-AndroidAssets -RepoRoot $RepoRoot
    }
    
    Write-LogHeader "Bootstrap Complete!"
}

# Export functions
Export-ModuleMember -Function @(
    'Write-LogInfo',
    'Write-LogWarn',
    'Write-LogError',
    'Write-LogHeader',
    'Bootstrap-CoMaps',
    'Bootstrap-ApplyPatches',
    'Bootstrap-Boost',
    'Bootstrap-Data',
    'Bootstrap-AndroidAssets',
    'Bootstrap-Full'
)
