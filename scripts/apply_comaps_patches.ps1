#Requires -Version 7.0
<#
.SYNOPSIS
    Applies patch files from patches/comaps/ to thirdparty/comaps.

.DESCRIPTION
    This script applies all patch files in patches/comaps/ directory
    to the thirdparty/comaps checkout. Patches are applied in sorted order.

.PARAMETER DryRun
    If specified, shows what would be applied without making changes.

.PARAMETER Force
    If specified, attempts to apply patches even if they don't apply cleanly.

.EXAMPLE
    .\scripts\apply_comaps_patches.ps1

.EXAMPLE
    .\scripts\apply_comaps_patches.ps1 -DryRun

.EXAMPLE
    .\scripts\apply_comaps_patches.ps1 -Force
#>

param(
    [switch]$DryRun,
    [switch]$Force
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
    $applied = 0
    $skipped = 0
    $failed = 0

    foreach ($patchFile in $patchFiles) {
        Write-Host "Applying: $($patchFile.Name)" -ForegroundColor Cyan
        
        $patchPath = $patchFile.FullName
        
        # Check if patch can be applied
        $checkArgs = @('apply', '--check', $patchPath)
        $checkResult = & git @checkArgs 2>&1
        $canApply = $LASTEXITCODE -eq 0

        if ($DryRun) {
            if ($canApply) {
                Write-Host "  [DRY RUN] Would apply successfully" -ForegroundColor Green
                $applied++
            } else {
                Write-Host "  [DRY RUN] Would fail or already applied" -ForegroundColor Yellow
                $skipped++
            }
            continue
        }

        if ($canApply) {
            # Apply the patch
            $applyArgs = @('apply', $patchPath)
            $applyResult = & git @applyArgs 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Applied successfully" -ForegroundColor Green
                $applied++
            } else {
                Write-Host "  Failed to apply: $applyResult" -ForegroundColor Red
                $failed++
            }
        } else {
            # Check if already applied by attempting reverse
            $reverseArgs = @('apply', '--check', '--reverse', $patchPath)
            $reverseResult = & git @reverseArgs 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Already applied (skipping)" -ForegroundColor Yellow
                $skipped++
            } elseif ($Force) {
                # Try to apply with 3-way merge
                Write-Host "  Attempting 3-way merge..." -ForegroundColor Yellow
                $forceArgs = @('apply', '--3way', $patchPath)
                $forceResult = & git @forceArgs 2>&1
                
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  Applied with 3-way merge" -ForegroundColor Green
                    $applied++
                } else {
                    Write-Host "  Failed even with force: $forceResult" -ForegroundColor Red
                    $failed++
                }
            } else {
                Write-Host "  Cannot apply (use -Force to attempt anyway)" -ForegroundColor Red
                $failed++
            }
        }
    }

    Write-Host ""
    Write-Host "=== Summary ===" -ForegroundColor Cyan
    Write-Host "Applied: $applied" -ForegroundColor Green
    Write-Host "Skipped: $skipped" -ForegroundColor Yellow
    Write-Host "Failed:  $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Gray' })

    if ($failed -gt 0) {
        exit 1
    }

} finally {
    Pop-Location
}
