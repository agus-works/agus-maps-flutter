#Requires -Version 7.0
<#
.SYNOPSIS
    Fetches/clones the CoMaps repository and applies patches.

.DESCRIPTION
    This script clones or updates the CoMaps repository in thirdparty/comaps
    and applies all patches from patches/comaps/.

.PARAMETER Branch
    The branch to checkout. Defaults to 'master'.

.PARAMETER Reset
    If specified, performs a hard reset before applying patches.

.PARAMETER SkipPatches
    If specified, skips applying patches after checkout.

.EXAMPLE
    .\scripts\fetch_comaps.ps1

.EXAMPLE
    .\scripts\fetch_comaps.ps1 -Branch develop -Reset
#>

param(
    [string]$Branch = 'master',
    [switch]$Reset,
    [switch]$SkipPatches
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Configuration
$ComapsGitUrl = 'https://github.com/AliAnalytics/comaps.git'

# Script paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$ThirdpartyDir = Join-Path $RepoRoot 'thirdparty'
$ComapsDir = Join-Path $ThirdpartyDir 'comaps'
$ApplyPatchesScript = Join-Path $ScriptDir 'apply_comaps_patches.ps1'

Write-Host "=== Fetching CoMaps ===" -ForegroundColor Cyan
Write-Host "Repository URL: $ComapsGitUrl"
Write-Host "Target Directory: $ComapsDir"
Write-Host "Branch: $Branch"
Write-Host ""

# Create thirdparty directory if needed
if (-not (Test-Path $ThirdpartyDir)) {
    New-Item -ItemType Directory -Path $ThirdpartyDir -Force | Out-Null
    Write-Host "Created thirdparty directory" -ForegroundColor Green
}

# Clone or update repository
if (Test-Path (Join-Path $ComapsDir '.git')) {
    Write-Host "CoMaps repository already exists" -ForegroundColor Yellow
    
    Push-Location $ComapsDir
    try {
        if ($Reset) {
            Write-Host "Performing hard reset..." -ForegroundColor Yellow
            git fetch origin 2>&1 | Out-Null
            git checkout $Branch 2>&1 | Out-Null
            git reset --hard "origin/$Branch" 2>&1 | Out-Null
            Write-Host "Reset to origin/$Branch" -ForegroundColor Green
        } else {
            # Just fetch updates
            Write-Host "Fetching updates..." -ForegroundColor Gray
            git fetch origin 2>&1 | Out-Null
            
            # Check current branch
            $currentBranch = git rev-parse --abbrev-ref HEAD 2>&1
            if ($currentBranch -ne $Branch) {
                Write-Host "Switching to branch: $Branch" -ForegroundColor Yellow
                git checkout $Branch 2>&1 | Out-Null
            }
            
            Write-Host "Current branch: $currentBranch" -ForegroundColor Gray
        }
        
        # Show current commit
        $commit = git rev-parse --short HEAD 2>&1
        $commitMsg = git log -1 --format="%s" 2>&1
        Write-Host "Current commit: $commit - $commitMsg" -ForegroundColor Gray
        
    } finally {
        Pop-Location
    }
} else {
    Write-Host "Cloning CoMaps repository..." -ForegroundColor Green
    
    # Remove directory if it exists but isn't a git repo
    if (Test-Path $ComapsDir) {
        Remove-Item -Path $ComapsDir -Recurse -Force
    }
    
    # Clone the repository
    $cloneArgs = @('clone', '--branch', $Branch, '--depth', '1', $ComapsGitUrl, $ComapsDir)
    & git @cloneArgs 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor Gray }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to clone CoMaps repository"
        exit 1
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
