#Requires -Version 7.0
<#
.SYNOPSIS
    Applies patch files from patches/comaps/ to thirdparty/comaps.

.DESCRIPTION
    This script applies all patch files in patches/comaps/ directory
    to the thirdparty/comaps checkout. Patches are applied in sorted order.
    
    Patches that target non-existent files (e.g., uninitialized submodules)
    are skipped with a warning rather than failing the entire process.
    
    By default, the script:
    1. Resets the CoMaps working tree (and submodules) to HEAD
    2. Applies all patches using git apply (with fallback methods)

.PARAMETER DryRun
    If specified, shows what would be applied without making changes.

.PARAMETER NoReset
    If specified, skips the git reset step (not recommended).

.EXAMPLE
    .\scripts\apply_comaps_patches.ps1

.EXAMPLE
    .\scripts\apply_comaps_patches.ps1 -DryRun

.EXAMPLE
    .\scripts\apply_comaps_patches.ps1 -NoReset
#>

param(
    [switch]$DryRun,
    [switch]$NoReset
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$ComapsDir = Join-Path $RepoRoot 'thirdparty' 'comaps'
$PatchesDir = Join-Path $RepoRoot 'patches' 'comaps'

Write-Host "=== Applying CoMaps Patches ===" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "(DRY RUN - no changes will be made)" -ForegroundColor Yellow
}
Write-Host "Repository Root: $RepoRoot"
Write-Host "CoMaps Directory: $ComapsDir"
Write-Host "Patches Directory: $PatchesDir"
Write-Host ""

# Verify directories exist
if (-not (Test-Path $ComapsDir)) {
    Write-Error "CoMaps directory not found: $ComapsDir"
    exit 1
}

if (-not (Test-Path $PatchesDir)) {
    Write-Host "Patches directory not found: $PatchesDir" -ForegroundColor Yellow
    Write-Host "No patches to apply."
    exit 0
}

# Get all patch files in sorted order
$patchFiles = Get-ChildItem -Path $PatchesDir -Filter "*.patch" -ErrorAction SilentlyContinue |
              Sort-Object Name

if ($patchFiles.Count -eq 0) {
    Write-Host "No patch files found in: $PatchesDir" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($patchFiles.Count) patch file(s) to apply:" -ForegroundColor Green
$patchFiles | ForEach-Object { Write-Host "  - $($_.Name)" }
Write-Host ""

# Apply each patch
Push-Location $ComapsDir
try {
    # Reset working tree to HEAD before applying patches
    if (-not $NoReset -and -not $DryRun) {
        Write-Host "Resetting working tree to HEAD..." -ForegroundColor Yellow
        
        # Force checkout to discard all local changes
        & git checkout --force HEAD 2>&1 | Out-Null
        & git clean -fd 2>&1 | Out-Null
        
        # Reset submodules
        Write-Host "Resetting submodules..." -ForegroundColor Yellow
        & git submodule foreach --recursive 'git checkout --force HEAD 2>/dev/null || true' 2>&1 | Out-Null
        & git submodule foreach --recursive 'git clean -fd 2>/dev/null || true' 2>&1 | Out-Null
        
        Write-Host "Working tree reset complete" -ForegroundColor Green
        Write-Host ""
    } elseif ($NoReset) {
        Write-Host "Skipping reset (-NoReset specified)" -ForegroundColor Yellow
        Write-Host ""
    }

    $applied = 0
    $skipped = 0
    $failed = 0

    foreach ($patchFile in $patchFiles) {
        $patchPath = $patchFile.FullName
        $patchName = $patchFile.Name
        
        # Extract the target file and check if this is a new file patch
        $targetFile = $null
        $isNewFilePatch = $false
        $patchContent = Get-Content $patchPath -TotalCount 10
        foreach ($line in $patchContent) {
            if ($line -match 'diff --git a/(.+?) b/') {
                $targetFile = $Matches[1]
            }
            if ($line -match '^new file mode') {
                $isNewFilePatch = $true
            }
            if ($line -match '--- /dev/null') {
                $isNewFilePatch = $true
            }
        }
        
        # Check if target file exists (skip patches for uninitialized submodules)
        # BUT allow patches that create new files (from /dev/null)
        if ($targetFile -and -not $isNewFilePatch -and -not (Test-Path $targetFile)) {
            Write-Host "Skipping: $patchName (target '$targetFile' does not exist)" -ForegroundColor Yellow
            $skipped++
            continue
        }
        
        Write-Host "Applying: $patchName" -ForegroundColor Cyan
        
        if ($DryRun) {
            # Check if patch can be applied
            $checkArgs = @('apply', '--check', $patchPath)
            $checkResult = & git @checkArgs 2>&1
            $canApply = $LASTEXITCODE -eq 0
            
            if ($canApply) {
                Write-Host "  [DRY RUN] Would apply successfully" -ForegroundColor Green
                $applied++
            } else {
                # Check if already applied
                $reverseArgs = @('apply', '--check', '--reverse', $patchPath)
                & git @reverseArgs 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  [DRY RUN] Already applied (would skip)" -ForegroundColor Yellow
                    $skipped++
                } else {
                    Write-Host "  [DRY RUN] Would fail" -ForegroundColor Red
                    $failed++
                }
            }
            continue
        }

        # Try direct apply first (fastest, works when blob hashes match)
        $applyArgs = @('apply', '--whitespace=nowarn', $patchPath)
        $applyResult = & git @applyArgs 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Applied successfully" -ForegroundColor Green
            $applied++
        } else {
            # Direct apply failed - try 3-way merge as fallback
            $apply3Args = @('apply', '--3way', '--whitespace=nowarn', $patchPath)
            $apply3Result = & git @apply3Args 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Applied successfully (3-way merge)" -ForegroundColor Green
                $applied++
            } else {
                # Check if already applied by attempting reverse
                $reverseArgs = @('apply', '--check', '--reverse', $patchPath)
                $reverseResult = & git @reverseArgs 2>&1
                
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
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    Write-Host "Applied: $applied" -ForegroundColor Green
    Write-Host "Skipped: $skipped" -ForegroundColor Yellow
    Write-Host "Failed:  $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Gray' })

    if ($failed -gt 0) {
        Write-Host ""
        Write-Host "Some patches failed. Build may still succeed if patches were optional." -ForegroundColor Yellow
    }

} finally {
    Pop-Location
}
