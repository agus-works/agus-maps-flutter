#Requires -Version 7.0
<#
.SYNOPSIS
    Fetches/clones the CoMaps repository and applies patches.

.DESCRIPTION
    This script clones or updates the CoMaps repository in thirdparty/comaps
    and applies all patches from patches/comaps/.
    
    Matches behavior of fetch_comaps.sh (uses specific tag v2025.12.11-2).

.PARAMETER Tag
    The tag to checkout. Defaults to 'v2025.12.11-2'.

.PARAMETER SkipPatches
    If specified, skips applying patches after checkout.

.EXAMPLE
    .\scripts\fetch_comaps.ps1

.EXAMPLE
    .\scripts\fetch_comaps.ps1 -Tag v2025.12.11-2
#>

param(
    [string]$Tag = 'v2025.12.11-2',
    [switch]$SkipPatches
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Configuration - use HTTPS URL for CoMaps (same as bash script)
$ComapsGitUrl = 'https://github.com/comaps/comaps.git'
$ComapsTag = 'v2025.12.11-2'

# Script paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$ThirdpartyDir = Join-Path $RepoRoot 'thirdparty'
$ComapsDir = Join-Path $ThirdpartyDir 'comaps'
$ApplyPatchesScript = Join-Path $ScriptDir 'apply_comaps_patches.ps1'

Write-Host "=== Fetching CoMaps ===" -ForegroundColor Cyan
Write-Host "Repository URL: $ComapsGitUrl"
Write-Host "Target Directory: $ComapsDir"
Write-Host "Tag: $Tag (default: $ComapsTag)"
Write-Host ""

# Create thirdparty directory if needed
if (-not (Test-Path $ThirdpartyDir)) {
    New-Item -ItemType Directory -Path $ThirdpartyDir -Force | Out-Null
    Write-Host "Created thirdparty directory" -ForegroundColor Green
}

# Clone or update repository
if (Test-Path (Join-Path $ComapsDir '.git')) {
    Write-Host "CoMaps repository already exists, fetching tags..." -ForegroundColor Yellow
    
    Push-Location $ComapsDir
    try {
        & git fetch --tags --prune 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
        
        Write-Host "Checking out tag: $Tag" -ForegroundColor Yellow
        # Use detached HEAD for clean tag checkout
        & git checkout --detach $Tag 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to checkout tag: $Tag"
            exit 1
        }
        
        # Show current commit
        $commit = git rev-parse --short HEAD 2>&1
        $describe = git describe --tags --always --dirty 2>&1
        Write-Host "At commit: $commit ($describe)" -ForegroundColor Gray
        
    } finally {
        Pop-Location
    }
} else {
    Write-Host "Cloning CoMaps repository..." -ForegroundColor Green
    
    # Remove directory if it exists but isn't a git repo
    if (Test-Path $ComapsDir) {
        Remove-Item -Path $ComapsDir -Recurse -Force
    }
    
    # Clone without checkout, then configure git settings before checkout
    # This ensures autocrlf is set correctly before files are written
    # Note: Do NOT use --depth 1 as we need full submodule initialization for patches
    $cloneArgs = @('clone', '--no-checkout', '--branch', $Tag, $ComapsGitUrl, $ComapsDir)
    Write-Host "Cloning (no checkout)..." -ForegroundColor Gray
    & git @cloneArgs 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to clone CoMaps repository"
        exit 1
    }
    
    # Configure git to preserve line endings BEFORE checkout
    # This is critical for patch application to work correctly
    Push-Location $ComapsDir
    try {
        Write-Host "Configuring git settings..." -ForegroundColor Gray
        & git config core.autocrlf false
        & git config core.eol lf
        
        Write-Host "Checking out files..." -ForegroundColor Gray
        & git checkout HEAD 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
        
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to checkout files"
            exit 1
        }
        
        $commit = git rev-parse --short HEAD 2>&1
        $describe = git describe --tags --always 2>&1
        Write-Host "At commit: $commit ($describe)" -ForegroundColor Gray
    } finally {
        Pop-Location
    }
    
    Write-Host "Cloned successfully" -ForegroundColor Green
}

# Initialize submodules
Write-Host ""
Write-Host "Initializing submodules..." -ForegroundColor Gray
Push-Location $ComapsDir
try {
    git submodule update --init --recursive 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Submodule initialization had issues (may be non-fatal)"
    }
} finally {
    Pop-Location
}

# Apply patches
if (-not $SkipPatches) {
    Write-Host ""
    if (Test-Path $ApplyPatchesScript) {
        Write-Host "Applying patches..." -ForegroundColor Cyan
        & $ApplyPatchesScript
    } else {
        Write-Warning "Patch script not found: $ApplyPatchesScript"
    }
}

Write-Host ""
Write-Host "=== CoMaps fetch complete ===" -ForegroundColor Cyan
