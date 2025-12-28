#Requires -Version 7.0
<#!
.SYNOPSIS
  Copies essential CoMaps data files into the example app assets.

.DESCRIPTION
  Source:   ./thirdparty/comaps/data
  Dest:     ./example/assets/comaps_data

  This is the PowerShell equivalent of scripts/copy_comaps_data.sh.
  It is PowerShell 7+ compatible.
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot ".."))
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$comapsData = Join-Path $RepoRoot "thirdparty\comaps\data"
$destData = Join-Path $RepoRoot "example\assets\comaps_data"

Write-Host "Copying CoMaps data files to example assets..." -ForegroundColor Cyan
Write-Host "  Source: $comapsData"
Write-Host "  Dest:   $destData"

if (!(Test-Path $comapsData)) {
  if (Test-Path $destData) {
    Write-Warning "CoMaps data directory not found at $comapsData"
    Write-Warning "Using existing data at $destData"
    exit 0
  } else {
    throw "CoMaps data directory not found at $comapsData and no existing data at $destData. Run scripts/fetch_comaps.ps1 first."
  }
}

New-Item -ItemType Directory -Force -Path $destData | Out-Null

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
  $dst = Join-Path $destData $file
  if (Test-Path $src) {
    Copy-Item -Force -Path $src -Destination $dst
    Write-Host "  ✓ $file" -ForegroundColor Green
  } else {
    Write-Host "  ✗ $file (not found)" -ForegroundColor Yellow
  }
}

$dirsToCopy = @(
  "categories-strings",
  "countries-strings",
  "fonts",
  "symbols",
  "styles"
)

foreach ($dir in $dirsToCopy) {
  $srcDir = Join-Path $comapsData $dir
  $dstDir = Join-Path $destData $dir
  if (Test-Path $srcDir) {
    New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
    Copy-Item -Force -Recurse -Path (Join-Path $srcDir '*') -Destination $dstDir
    Write-Host "  ✓ $dir/" -ForegroundColor Green
  }
}

Write-Host ""
Write-Host "Data files copied to: $destData" -ForegroundColor Cyan
