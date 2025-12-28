#Requires -Version 7.0
<#
.SYNOPSIS
    Bootstrap Android dependencies on Windows.

.DESCRIPTION
    This script prepares the development environment for building the Android
    version of agus_maps_flutter on a Windows workstation.

    What it does:
    - Fetches ./thirdparty/comaps at COMAPS_TAG
    - Initializes ALL submodules (required for patches)
    - Applies patches from ./patches/comaps (superset for all platforms)
    - Prepares boost headers
    - Copies CoMaps data files
    - Copies Android-specific assets (fonts)

.PARAMETER ComapsTag
    Git tag/commit to checkout. Defaults to v2025.12.11-2.

.PARAMETER SkipPatches
    Skip applying patches (useful for debugging).

.PARAMETER Force
    Force re-bootstrap even if already done.

.EXAMPLE
    .\scripts\bootstrap_android.ps1

.EXAMPLE
    .\scripts\bootstrap_android.ps1 -Force

.NOTES
    This is the Windows PowerShell 7+ equivalent of scripts/bootstrap_android.sh.
    It uses the shared BootstrapCommon.psm1 module for core logic.
#>

[CmdletBinding()]
param(
    [string]$ComapsTag,
    [switch]$SkipPatches,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Script paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

# Import common bootstrap module
Import-Module (Join-Path $ScriptDir 'BootstrapCommon.psm1') -Force

# Set COMAPS_TAG if provided
if ($ComapsTag) {
    $env:COMAPS_TAG = $ComapsTag
}

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Bootstrap Android Dependencies (Windows)" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Run full bootstrap targeting Android
if ($SkipPatches) {
    Bootstrap-CoMaps -RepoRoot $RepoRoot
    Bootstrap-Boost -RepoRoot $RepoRoot
    Bootstrap-Data -RepoRoot $RepoRoot
    Bootstrap-AndroidAssets -RepoRoot $RepoRoot
} else {
    Bootstrap-Full -RepoRoot $RepoRoot -Platform 'android'
}

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Bootstrap Complete!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Run the example app:"
Write-Host "     cd example" -ForegroundColor White
Write-Host "     flutter run" -ForegroundColor White
Write-Host ""
Write-Host "  2. Or build Android binaries:"
Write-Host "     .\scripts\build_binaries_android.ps1" -ForegroundColor White
Write-Host ""
