#Requires -Version 7.0
<#
.SYNOPSIS
    Validates that patch files accurately reflect current modifications in thirdparty/comaps.

.DESCRIPTION
    This script compares the current state of modified files in thirdparty/comaps
    against the patch files in patches/comaps/ to ensure they are in sync.

.EXAMPLE
    .\scripts\validate_patches.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$ComapsDir = Join-Path $RepoRoot 'thirdparty' 'comaps'
$PatchesDir = Join-Path $RepoRoot 'patches' 'comaps'

Write-Host "=== Validating CoMaps Patches ===" -ForegroundColor Cyan
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
    Write-Warning "Patches directory not found: $PatchesDir"
    Write-Host "No patches to validate."
    exit 0
}

# Get current modifications
Push-Location $ComapsDir
try {
    $currentDiff = git diff 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to get current diff: $currentDiff"
        exit 1
    }

    # Get list of modified files
    $modifiedFiles = git diff --name-only 2>&1
    $modifiedList = @()
    if (-not [string]::IsNullOrWhiteSpace($modifiedFiles)) {
        $modifiedList = $modifiedFiles -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    Write-Host "Currently modified files in thirdparty/comaps: $($modifiedList.Count)" -ForegroundColor Gray
    $modifiedList | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
    Write-Host ""

    # Get all patch files
    $patchFiles = Get-ChildItem -Path $PatchesDir -Filter "*.patch" -ErrorAction SilentlyContinue |
                  Sort-Object Name

    if ($patchFiles.Count -eq 0) {
        if ($modifiedList.Count -gt 0) {
            Write-Warning "No patch files found, but there are $($modifiedList.Count) modified files!"
            Write-Host "Run .\scripts\regenerate_patches.ps1 to create patches." -ForegroundColor Yellow
            exit 1
        }
        Write-Host "No patches and no modifications. All clean!" -ForegroundColor Green
        exit 0
    }

    Write-Host "Found $($patchFiles.Count) patch file(s):" -ForegroundColor Gray
    $patchFiles | ForEach-Object { Write-Host "  - $($_.Name)" -ForegroundColor Gray }
    Write-Host ""

    # Combine all patches and compare
    $combinedPatches = ""
    foreach ($patchFile in $patchFiles) {
        $patchContent = Get-Content $patchFile.FullName -Raw -ErrorAction SilentlyContinue
        if ($patchContent) {
            $combinedPatches += $patchContent
        }
    }

    # Normalize line endings for comparison
    $normalizedCurrent = $currentDiff -replace "`r`n", "`n" -replace "`r", "`n"
    $normalizedPatches = $combinedPatches -replace "`r`n", "`n" -replace "`r", "`n"

    # Trim whitespace
    $normalizedCurrent = $normalizedCurrent.Trim()
    $normalizedPatches = $normalizedPatches.Trim()

    if ($normalizedCurrent -eq $normalizedPatches) {
        Write-Host "=== Validation PASSED ===" -ForegroundColor Green
        Write-Host "All patches are in sync with current modifications."
        exit 0
    } else {
        Write-Host "=== Validation FAILED ===" -ForegroundColor Red
        Write-Host "Patches do not match current modifications."
        Write-Host ""
        Write-Host "Current diff length: $($normalizedCurrent.Length) chars" -ForegroundColor Yellow
        Write-Host "Patches length: $($normalizedPatches.Length) chars" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Run .\scripts\regenerate_patches.ps1 to update patches." -ForegroundColor Yellow
        exit 1
    }

} finally {
    Pop-Location
}
