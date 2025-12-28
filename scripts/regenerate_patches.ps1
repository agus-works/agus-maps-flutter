#Requires -Version 7.0
<#
.SYNOPSIS
    Regenerates patch files from current modifications in thirdparty/comaps.

.DESCRIPTION
    This script scans the thirdparty/comaps directory for modified files
    and generates individual patch files in patches/comaps/ directory.
    Each modified file gets its own patch file for easier management.

.EXAMPLE
    .\scripts\regenerate_patches.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$ComapsDir = Join-Path $RepoRoot 'thirdparty' 'comaps'
$PatchesDir = Join-Path $RepoRoot 'patches' 'comaps'

Write-Host "=== Regenerating CoMaps Patches ===" -ForegroundColor Cyan
Write-Host "Repository Root: $RepoRoot"
Write-Host "CoMaps Directory: $ComapsDir"
Write-Host "Patches Directory: $PatchesDir"
Write-Host ""

# Verify comaps directory exists
if (-not (Test-Path $ComapsDir)) {
    Write-Error "CoMaps directory not found: $ComapsDir"
    exit 1
}

# Verify it's a git repository
if (-not (Test-Path (Join-Path $ComapsDir '.git'))) {
    Write-Error "CoMaps directory is not a git repository"
    exit 1
}

# Create patches directory if needed
if (-not (Test-Path $PatchesDir)) {
    New-Item -ItemType Directory -Path $PatchesDir -Force | Out-Null
    Write-Host "Created patches directory: $PatchesDir" -ForegroundColor Green
}

# Get list of modified files
Push-Location $ComapsDir
try {
    $modifiedFiles = git diff --name-only 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to get modified files: $modifiedFiles"
        exit 1
    }

    if ([string]::IsNullOrWhiteSpace($modifiedFiles)) {
        Write-Host "No modified files found in thirdparty/comaps" -ForegroundColor Yellow
        exit 0
    }

    $fileList = $modifiedFiles -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    Write-Host "Found $($fileList.Count) modified file(s):" -ForegroundColor Green
    $fileList | ForEach-Object { Write-Host "  - $_" }
    Write-Host ""

    # Generate patches for each modified file
    $patchIndex = 1
    $existingPatches = Get-ChildItem -Path $PatchesDir -Filter "*.patch" -ErrorAction SilentlyContinue |
                       Sort-Object Name

    # Find the highest existing patch number
    $maxPatchNum = 0
    foreach ($patch in $existingPatches) {
        if ($patch.Name -match '^(\d{4})-') {
            $num = [int]$Matches[1]
            if ($num -gt $maxPatchNum) {
                $maxPatchNum = $num
            }
        }
    }

    foreach ($file in $fileList) {
        # Generate a safe filename from the path
        $safeName = $file -replace '[/\\]', '-' -replace '\.', '-'
        
        # Check if a patch for this file already exists
        $existingPatch = $existingPatches | Where-Object { 
            $_.Name -match [regex]::Escape($safeName) -or
            (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match [regex]::Escape($file)
        } | Select-Object -First 1

        if ($existingPatch) {
            # Update existing patch
            $patchPath = $existingPatch.FullName
            Write-Host "Updating existing patch: $($existingPatch.Name)" -ForegroundColor Yellow
        } else {
            # Create new patch with next available number
            $maxPatchNum++
            $patchNum = $maxPatchNum.ToString("D4")
            $patchName = "$patchNum-$safeName.patch"
            $patchPath = Join-Path $PatchesDir $patchName
            Write-Host "Creating new patch: $patchName" -ForegroundColor Green
        }

        # Generate the patch
        $diff = git diff $file 2>&1
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($diff)) {
            $diff | Out-File -FilePath $patchPath -Encoding utf8NoBOM -Force
            Write-Host "  Saved to: $patchPath" -ForegroundColor Gray
        } else {
            Write-Warning "No diff generated for: $file"
        }
    }

    Write-Host ""
    Write-Host "=== Patch regeneration complete ===" -ForegroundColor Cyan

} finally {
    Pop-Location
}
