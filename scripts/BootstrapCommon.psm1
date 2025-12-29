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
$script:SEVENZ_PATH = 'C:\Program Files\7-Zip\7z.exe'
$script:THIRDPARTY_ARCHIVE = '.thirdparty.7z'

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
# Test-7ZipAvailable - Check if 7-Zip is available
# ============================================================================

function Test-7ZipAvailable {
    [CmdletBinding()]
    param()
    
    return (Test-Path $script:SEVENZ_PATH)
}

# ============================================================================
# Compress-ThirdParty - Compress thirdparty directory to .thirdparty.7z
# ============================================================================

function Compress-ThirdParty {
    [CmdletBinding()]
    param(
        [string]$RepoRoot
    )
    
    if (-not (Test-7ZipAvailable)) {
        Write-LogWarn "7-Zip not found at $script:SEVENZ_PATH - skipping compression"
        return $false
    }
    
    $thirdpartyDir = Join-Path $RepoRoot 'thirdparty'
    $archivePath = Join-Path $RepoRoot $script:THIRDPARTY_ARCHIVE
    
    if (-not (Test-Path $thirdpartyDir)) {
        Write-LogWarn "Thirdparty directory not found - nothing to compress"
        return $false
    }
    
    Write-LogHeader "Compressing thirdparty to $script:THIRDPARTY_ARCHIVE"
    Write-LogInfo "This may take several minutes..."
    
    # Remove existing archive if it exists
    if (Test-Path $archivePath) {
        Remove-Item -Path $archivePath -Force
        Write-LogInfo "Removed existing archive"
    }
    
    # Create archive with maximum compression
    # -t7z: 7z format
    # -mx=9: Maximum compression
    # -mfb=64: 64 fast bytes
    # -md=32m: 32MB dictionary
    Push-Location $RepoRoot
    try {
        $startTime = Get-Date
        & $script:SEVENZ_PATH a -t7z -mx=9 -mfb=64 -md=32m $archivePath "thirdparty" 2>&1 | ForEach-Object { 
            if ($_ -match '^\s*\d+%') {
                Write-Host "`r  $_" -NoNewline -ForegroundColor Gray
            }
        }
        Write-Host ""  # New line after progress
        
        if ($LASTEXITCODE -ne 0) {
            Write-LogError "Failed to create archive"
            return $false
        }
        
        $elapsed = (Get-Date) - $startTime
        $sizeMB = [math]::Round((Get-Item $archivePath).Length / 1MB, 2)
        Write-LogInfo "Archive created: $sizeMB MB in $([math]::Round($elapsed.TotalMinutes, 1)) minutes"
        return $true
    } finally {
        Pop-Location
    }
}

# ============================================================================
# Expand-ThirdParty - Extract .thirdparty.7z to thirdparty directory
# ============================================================================

function Expand-ThirdParty {
    [CmdletBinding()]
    param(
        [string]$RepoRoot
    )
    
    if (-not (Test-7ZipAvailable)) {
        Write-LogWarn "7-Zip not found at $script:SEVENZ_PATH"
        return $false
    }
    
    $archivePath = Join-Path $RepoRoot $script:THIRDPARTY_ARCHIVE
    $thirdpartyDir = Join-Path $RepoRoot 'thirdparty'
    
    if (-not (Test-Path $archivePath)) {
        Write-LogInfo "No cached archive found at $archivePath"
        return $false
    }
    
    Write-LogHeader "Extracting $script:THIRDPARTY_ARCHIVE"
    Write-LogInfo "This may take a few minutes..."
    
    # Remove existing thirdparty directory if present
    if (Test-Path $thirdpartyDir) {
        Write-LogInfo "Removing existing thirdparty directory..."
        Remove-Item -Path $thirdpartyDir -Recurse -Force
    }
    
    Push-Location $RepoRoot
    try {
        $startTime = Get-Date
        # -y: Yes to all prompts
        # -o: Output directory (extracts to current dir, archive contains 'thirdparty' folder)
        & $script:SEVENZ_PATH x -y $archivePath 2>&1 | ForEach-Object {
            if ($_ -match '^\s*\d+%') {
                Write-Host "`r  $_" -NoNewline -ForegroundColor Gray
            }
        }
        Write-Host ""  # New line after progress
        
        if ($LASTEXITCODE -ne 0) {
            Write-LogError "Failed to extract archive"
            return $false
        }
        
        $elapsed = (Get-Date) - $startTime
        Write-LogInfo "Extracted in $([math]::Round($elapsed.TotalSeconds, 1)) seconds"
        return $true
    } finally {
        Pop-Location
    }
}

# ============================================================================
# Test-ThirdPartyArchive - Check if cached archive exists
# ============================================================================

function Test-ThirdPartyArchive {
    [CmdletBinding()]
    param(
        [string]$RepoRoot
    )
    
    $archivePath = Join-Path $RepoRoot $script:THIRDPARTY_ARCHIVE
    return (Test-Path $archivePath)
}

# ============================================================================
# Bootstrap-CoMaps - Fetch CoMaps source and initialize submodules
# ============================================================================

function Bootstrap-CoMaps {
    [CmdletBinding()]
    param(
        [string]$RepoRoot,
        [string]$Tag = $script:COMAPS_TAG,
        [switch]$SkipIfExists
    )

    Write-LogHeader "Bootstrapping CoMaps"
    
    $thirdpartyDir = Join-Path $RepoRoot 'thirdparty'
    $comapsDir = Join-Path $thirdpartyDir 'comaps'
    
    # Check if we can skip (used when extracted from cache)
    if ($SkipIfExists -and (Test-Path (Join-Path $comapsDir '.git'))) {
        Write-LogInfo "CoMaps already exists and SkipIfExists specified"
        return @{ FreshClone = $false }
    }
    
    # Create thirdparty directory if needed
    if (-not (Test-Path $thirdpartyDir)) {
        New-Item -ItemType Directory -Path $thirdpartyDir -Force | Out-Null
        Write-LogInfo "Created thirdparty directory"
    }
    
    $freshClone = $false
    
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
        $freshClone = $true
        
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
    return @{ FreshClone = $freshClone }
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
            
            # Extract target file and check if it's a new file patch
            $targetFile = $null
            $isNewFile = $false
            $patchContent = Get-Content $patchPath -TotalCount 10
            $firstLine = $patchContent | Select-Object -First 1
            if ($firstLine -match 'diff --git a/(.+?) b/') {
                $targetFile = $Matches[1]
            }
            # Check for new file indicator in patch header
            foreach ($line in $patchContent) {
                if ($line -match '^new file mode' -or $line -match '^\+\+\+ b/.+' -and ($patchContent | Where-Object { $_ -match '^--- /dev/null' })) {
                    $isNewFile = $true
                    break
                }
            }
            
            # Skip patches for uninitialized submodules (but allow new file patches)
            if ($targetFile -and -not $isNewFile) {
                # For modification patches, check if target directory exists (not file, since it could be in submodule)
                $targetDir = Split-Path -Parent $targetFile
                if ($targetDir -and -not (Test-Path $targetDir)) {
                    Write-LogWarn "Skipping $patchName (directory '$targetDir' does not exist - submodule not initialized?)"
                    $skipped++
                    continue
                }
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
        [string]$Platform = 'all',
        [switch]$NoCache
    )

    Write-LogHeader "Full Bootstrap for agus_maps_flutter"
    Write-LogInfo "Platform: $Platform"
    Write-LogInfo "CoMaps tag: $script:COMAPS_TAG"
    
    $thirdpartyDir = Join-Path $RepoRoot 'thirdparty'
    $comapsDir = Join-Path $thirdpartyDir 'comaps'
    $usedCache = $false
    $freshClone = $false
    
    # Check if we should try to use cache
    if (-not $NoCache) {
        # If thirdparty doesn't exist but cache does, extract it
        if (-not (Test-Path $comapsDir) -and (Test-ThirdPartyArchive -RepoRoot $RepoRoot)) {
            Write-LogInfo "Found cached archive - extracting instead of cloning"
            $extracted = Expand-ThirdParty -RepoRoot $RepoRoot
            if ($extracted) {
                $usedCache = $true
                Write-LogInfo "Successfully restored from cache"
            }
        }
    }
    
    # Step 1: Fetch CoMaps and initialize submodules (skip if we used cache)
    if ($usedCache) {
        $result = Bootstrap-CoMaps -RepoRoot $RepoRoot -SkipIfExists
    } else {
        $result = Bootstrap-CoMaps -RepoRoot $RepoRoot
        $freshClone = $result.FreshClone
    }
    
    # If we did a fresh clone and 7-zip is available, create cache BEFORE applying patches
    if ($freshClone -and -not $NoCache -and (Test-7ZipAvailable)) {
        Write-LogInfo "Creating cache archive from fresh clone (before patches)..."
        $compressed = Compress-ThirdParty -RepoRoot $RepoRoot
        if ($compressed) {
            Write-LogInfo "Cache created - subsequent bootstraps will be faster"
        }
    }
    
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
    'Test-7ZipAvailable',
    'Compress-ThirdParty',
    'Expand-ThirdParty',
    'Test-ThirdPartyArchive',
    'Bootstrap-CoMaps',
    'Bootstrap-ApplyPatches',
    'Bootstrap-Boost',
    'Bootstrap-Data',
    'Bootstrap-AndroidAssets',
    'Bootstrap-Full'
)
