# Agus Maps Flutter - Tool Documentation

This directory contains build tools, utilities, and helper scripts for the Agus Maps Flutter plugin development. All tools are written in Dart and can be executed via `dart run`.

## Table of Contents

- [Quick Start](#quick-start)
- [Main Tools](#main-tools)
  - [build.dart](#builddart---build-tool)
  - [asset_tools.dart](#asset_toolsdart---asset-tool)
  - [map_downloader.dart](#map_downloaderdart---map-downloader)
  - [check_mirrors.dart](#check_mirrorsdart---mirror-diagnostics)
  - [delete_non_tag_workflow_runs.dart](#delete_non_tag_workflow_runsdart---github-actions-run-cleanup)
- [Source Modules](#source-modules-toolsrc)
- [Environment Variables](#environment-variables)
- [Build Modes](#build-modes)
- [Platform-Specific Notes](#platform-specific-notes)

---

## Quick Start

```powershell
# Bootstrap CoMaps and prepare build environment
dart run tool/build.dart

# Build native binaries for all platforms (contributor mode)
dart run tool/build.dart --build-binaries

# Sync assets from thirdparty/comaps to example/assets
dart run tool/asset_tools.dart

# Download map files from CoMaps CDN
dart run tool/map_downloader.dart

# Check CDN mirror availability
dart run tool/check_mirrors.dart

# Preview cleanup of non-tag devops workflow runs (safe dry-run)
dart run tool/delete_non_tag_workflow_runs.dart
```

---

## Main Tools

### `build.dart` - Build Tool

The main build orchestration tool for contributors. Handles cloning CoMaps, applying patches, building native binaries, and preparing assets.

#### Usage

```powershell
dart run tool/build.dart [options]
```

#### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--build-binaries` | `-b` | Build native binaries for all platforms |
| `--skip-patches` | | Skip applying patches from `patches/comaps/` |
| `--no-cache` | | Disable local caching of thirdparty directory |
| `--platform <name>` | `-p` | Build specific platforms (can specify multiple) |
| `--help` | `-h` | Show help message |

#### Supported Platforms

- `android` - Android (arm64-v8a, armeabi-v7a, x86_64)
- `ios` - iOS (device + simulator XCFramework)
- `macos` - macOS (arm64 + x86_64 universal binary)
- `windows` - Windows (x64 DLL)
- `linux` - Linux (x64 shared library)

#### Examples

```powershell
# Bootstrap only (clone, patch, generate data)
dart run tool/build.dart

# Build binaries for all platforms supported by current OS
dart run tool/build.dart --build-binaries

# Build only Android and iOS binaries
dart run tool/build.dart --build-binaries --platform android --platform ios

# Build Windows binaries
dart run tool/build.dart --build-binaries --platform windows

# Skip patches (useful for debugging)
dart run tool/build.dart --skip-patches

# Disable caching (always fresh clone)
dart run tool/build.dart --no-cache
```

#### Build Workflow

1. **Bootstrap CoMaps** - Clone repository, checkout tag, initialize submodules
2. **Build Boost Headers** - Prepare Boost library headers
3. **Generate CoMaps Data** - Run data generation scripts (classificator, symbols, etc.)
4. **Sync Localized Strings** - Copy localization assets
5. **Copy Data Files** - Copy essential data files to example assets
6. **Update example pubspec assets** - Regenerate Flutter asset declarations
7. **Build Native Binaries** - Compile platform-specific libraries (if `--build-binaries`)
8. **Build Metal Shaders** - Compile Metal shaders for iOS/macOS (if applicable)
9. **Setup CocoaPods** - Run pod install for iOS/macOS (if applicable)

#### Caching

The build tool implements local caching for faster iteration:

- Cache file: `.thirdparty-{tag}.tar.gz` in repo root
- Cache is created AFTER clone, BEFORE patches
- If `thirdparty/` is deleted and cache exists, extract from cache
- Use `--no-cache` to disable caching behavior

---

### `asset_tools.dart` - Asset Tool

Synchronizes assets from thirdparty/comaps into the example app's assets directory and updates example pubspec asset declarations.

#### Usage

```powershell
dart run tool/asset_tools.dart [options]
```

#### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--copy-assets` | `-c` | Copy assets from thirdparty/comaps into example/assets |
| `--update-pubspec` | `-u` | Regenerate example/pubspec.yaml assets list from example/assets |
| `--help` | `-h` | Show help message |

#### Examples

```powershell
# Run all asset operations (copy + update pubspec)
dart run tool/asset_tools.dart

# Copy assets only
dart run tool/asset_tools.dart --copy-assets

# Update example/pubspec.yaml assets list only
dart run tool/asset_tools.dart --update-pubspec
```

#### Functions

- **syncLocalizedStringsAssets** - Copies localized strings from `thirdparty/comaps/iphone/Maps/LocalizedStrings/` to `example/assets/comaps_data/localized_types/`
- **copyDataFiles** - Copies essential CoMaps data files to `example/assets/comaps_data/`:
  - Configuration files: `classificator.txt`, `types.txt`, `categories.txt`, `visibility.txt`
  - Drawing rules: `drules_proto*.bin`, `drules_hash`
  - Map metadata: `countries.txt`, `countries_meta.txt`, `packed_polygons.bin`
  - Visual assets: `colors.txt`, `patterns.txt`, `transit_colors.txt`
  - Directories: `fonts/`, `symbols/`, `styles/`, `categories-strings/`, `countries-strings/`
  - ICU data: `icudt75l.dat`
- **updateExampleAssetsList** - Scans `example/assets/` and updates `example/pubspec.yaml` with proper asset declarations

---

### `map_downloader.dart` - Map Downloader

Cross-platform tool for downloading MWM map files from CoMaps CDN servers.

#### Usage

```powershell
dart run tool/map_downloader.dart [options]
```

#### Options

| Option | Short | Description |
|--------|-------|-------------|
| `--output-dir <path>` | `-o` | Output directory (default: `example/assets/maps`) |
| `--files <list>` | `-f` | Comma-separated MWM files to download (default: `World.mwm,WorldCoasts.mwm,Gibraltar.mwm`) |
| `--report <path>` | `-r` | Generate JSON report file |
| `--list-regions` | | List all available regions and exit |
| `--list-mirrors` | | List all mirrors and their status |
| `--snapshot <version>` | `-s` | Use specific snapshot version (YYMMDD format) |
| `--mirror <url>` | `-m` | Use specific mirror URL |
| `--force` | | Force re-download even if file exists |
| `--verbose` | `-v` | Enable verbose output |
| `--help` | `-h` | Show help message |

#### Examples

```powershell
# Download default base maps
dart run tool/map_downloader.dart

# Download specific maps to custom directory
dart run tool/map_downloader.dart -f "World.mwm,Germany_Berlin.mwm" -o ./maps

# List all available regions
dart run tool/map_downloader.dart --list-regions

# Generate JSON report with region metadata
dart run tool/map_downloader.dart --list-regions --report regions.json

# Check mirror status
dart run tool/map_downloader.dart --list-mirrors

# Use specific snapshot version
dart run tool/map_downloader.dart --snapshot 260113

# Force re-download existing files
dart run tool/map_downloader.dart --force
```

#### Features

- **Auto-discovery** - Automatically discovers best available mirror and latest snapshot
- **Progress tracking** - Visual progress bar for downloads
- **Caching** - Skips already downloaded files (use `--force` to override)
- **JSON reports** - Generate detailed download reports
- **Region metadata** - Fetch and display available regions with sizes

#### URL Structure

CoMaps CDN URL pattern: `<base>/maps/<snapshot>/<file>`
- Snapshot versions use YYMMDD format (e.g., `260113` = 2026-01-13)

---

### `check_mirrors.dart` - Mirror Diagnostics

Diagnostic tool for checking CoMaps CDN server availability.

#### Usage

```powershell
dart run tool/check_mirrors.dart
```

#### What It Does

1. **Queries Metaserver** - Gets active server list from CoMaps metaserver
2. **Probes Snapshots** - Dynamically discovers latest available snapshot (probes last 90 days)
3. **Tests Mirrors** - Checks each mirror's:
   - Base URL accessibility
   - Snapshot availability
   - Gibraltar.mwm download capability
4. **Generates Report** - Prints comprehensive status report with recommendations

#### Output

```
🔍 CoMaps CDN Mirror Availability Diagnostic Tool
==================================================

📅 Generated 90 candidate versions
   Range: 251030 to 260127

📡 Querying CoMaps metaserver...
   URL: https://maps.comaps.app/servers
   Response: 1 server(s) returned

Checking 2 CoMaps CDN servers...

  Checking CoMaps CDN...
    Base URL: OK (245ms)
    Snapshots: Found version 260113
    Gibraltar.mwm: OK (1.23 MB, partial download in 89ms)

================================================================================
COMAPS CDN MIRROR AVAILABILITY REPORT
================================================================================

📊 SUMMARY
Total mirrors checked: 2
Fully operational: 2 / 2

📋 RECOMMENDATIONS
Best CoMaps CDN: CoMaps CDN (245ms latency)
  URL: https://cdn.comaps.app/
  Latest snapshot: 260113
```

#### Exit Codes

- `0` - At least one operational mirror found
- `1` - No operational mirrors (critical failure)

---

### `delete_non_tag_workflow_runs.dart` - GitHub Actions Run Cleanup

Deletes GitHub Actions workflow runs that were **not** executed as a strict
release tag in format `vX.Y.Z`. This tool is scoped to one workflow and defaults
to `devops.yml`.

Default repository:

- `https://github.com/agus-works/agus-maps-flutter/`

Safety model:

- **Dry-run by default** (no deletion unless `--execute` is provided)
- **Skips active runs** (`queued` / `in_progress` / `waiting`)
- **Always deletes** `failure` and `cancelled` conclusions (when not active)
- **Always keeps** `success` conclusions
- For other non-success conclusions, keeps only runs whose `head_branch`
  matches `^v[0-9]+\.[0-9]+\.[0-9]+$`

#### Usage

```powershell
dart run tool/delete_non_tag_workflow_runs.dart [options]
```

#### Options

| Option | Description |
|--------|-------------|
| `--repo <value>` | Repository URL or `OWNER/REPO` (default: `https://github.com/agus-works/agus-maps-flutter/`) |
| `--workflow <value>` | Workflow file name or workflow ID (default: `devops.yml`) |
| `--execute` | Actually delete runs (otherwise dry-run) |
| `--max-pages <n>` | Maximum pages to fetch, 100 runs/page (default: `20`) |
| `--max-delete <n>` | Optional cap for number of deletions in execute mode |
| `--help`, `-h` | Show help message |

#### Examples

```powershell
# Safe preview with defaults (repo + workflow + dry-run)
dart run tool/delete_non_tag_workflow_runs.dart

# Explicit repository URL
dart run tool/delete_non_tag_workflow_runs.dart --repo https://github.com/agus-works/agus-maps-flutter/

# Perform deletions
dart run tool/delete_non_tag_workflow_runs.dart --execute

# Perform at most 5 deletions in one run
dart run tool/delete_non_tag_workflow_runs.dart --execute --max-delete 5
```

---

## Source Modules (`tool/src/`)

The `tool/src/` directory contains reusable modules that power the main tools:

### `config.dart` - Configuration

Build configuration constants and utilities.

| Constant | Value | Description |
|----------|-------|-------------|
| `defaultComapsTag` | `v2026.01.08-11` | Default CoMaps git tag |
| `flutterVersion` | `3.38.9` | Target Flutter version |
| `cmakeVersion` | `4.2.1` | CMake version |
| `ndkVersion` | `29.0.14206865` | Android NDK version |
| `buildType` | `Release` | CMake build type |
| `androidMinSdk` | `24` | Android minimum SDK |
| `androidAbis` | `['arm64-v8a', 'armeabi-v7a', 'x86_64']` | Android ABIs |
| `iosDeploymentTarget` | `15.6` | iOS deployment target |
| `macOSDeploymentTarget` | `12.0` | macOS deployment target |

**Functions:**
- `detectBuildMode()` - Detects consumer vs contributor mode
- `getComapsTag()` - Gets CoMaps tag from environment or default
- `getPackageVersion()` - Parses version from pubspec.yaml

---

### `build_runner.dart` - Build Orchestration

Main build workflow coordination.

**Classes:**
- `BuildRunnerConfig` - Configuration for build runner (mode, platforms, flags)

**Functions:**
- `runBuild(config)` - Main entry point for build workflow
- `_bootstrapComaps(tag)` - Clone, checkout, submodules, patches
- `_buildBoostHeaders()` - Build Boost library headers
- `_generateComapsData()` - Run data generation scripts
- `_buildPlatform(platform)` - Build binaries for specific platform
- `_buildAndroid()` - Build all Android ABIs
- `_buildiOS()` - Build iOS XCFramework
- `_buildMacOS()` - Build macOS XCFramework
- `_buildWindows()` - Build Windows DLL
- `_buildLinux()` - Build Linux shared library
- `_buildMetalShaders()` - Compile Metal shaders (macOS/iOS)
- `_setupCocoaPods(platform)` - Run pod install

---

### `cmake_build.dart` - CMake Integration

CMake build configuration and execution.

**Classes:**
- `CMakeBuildConfig` - CMake build configuration (source, build dir, variables, generator)

**Functions:**
- `buildWithCMake(config)` - Configure and build with CMake
- `buildAndroidAbi(abi)` - Build Android library for specific ABI
- `buildiOSXCFramework()` - Build iOS device + simulator XCFramework
- `buildMacOSXCFramework()` - Build macOS universal XCFramework
- `buildWindowsLibrary()` - Build Windows DLL
- `buildLinuxLibrary()` - Build Linux shared library

---

### `git_operations.dart` - Git Utilities

Git repository operations.

**Functions:**
- `cloneComaps(tag)` - Clone CoMaps repository
- `checkoutComapsTag(tag)` - Checkout specific tag
- `initSubmodules()` - Initialize submodules recursively (with Codeberg mirror fix)
- `getGitCommitHash()` - Get current commit hash
- `isGitAvailable()` - Check if git is available

---

### `patch_applicator.dart` - Patch Management

Applies patches from `patches/comaps/` directory.

**Functions:**
- `applyPatches()` - Apply all `.patch` files with multiple fallback methods:
  1. `git apply` (preferred)
  2. `git apply --3way` (merge conflicts)
  3. Check if already applied (reverse check)
  4. `patch -p1` (fallback)

---

### `assets_updater.dart` - Asset Management

Asset synchronization and pubspec management.

**Functions:**
- `syncLocalizedStringsAssets()` - Sync localized strings to assets/
- `copyDataFiles()` - Copy CoMaps data files to example/assets
- `updateFlutterAssetsList()` - Update pubspec.yaml assets section
- `updateExampleLocalizedTypesAssets()` - Update example pubspec with localized_types

---

### `file_operations.dart` - File Utilities

Cross-platform file operations.

**Functions:**
- `copyPath(source, dest)` - Copy file or directory recursively
- `removePath(target)` - Remove file or directory
- `ensureDir(dirPath)` - Ensure directory exists
- `pathExists(target)` - Check if path exists
- `fileExists(target)` - Check if file exists
- `dirExists(target)` - Check if directory exists

---

### `platform_detector.dart` - Platform Utilities

Platform detection and path utilities.

**Types:**
- `OSType` - Enum: `macos`, `linux`, `windows`

**Functions:**
- `detectOS()` - Detect current operating system
- `getCpuCores()` - Get number of CPU cores
- `getRepoRoot()` - Get repository root directory
- `getScriptDir()` - Get scripts/ directory path
- `getThirdpartyDir()` - Get thirdparty/ directory path
- `getComapsDir()` - Get thirdparty/comaps/ directory path
- `getBuildDir()` - Get build/ directory path
- `getPatchesDir()` - Get patches/comaps/ directory path
- `normalizePath(p)` - Normalize path for current platform
- `joinPaths(...)` - Join paths for current platform

---

### `process_runner.dart` - Process Execution

Process execution utilities.

**Functions:**
- `runProcess(exe, args, ...)` - Run process and return result
- `runProcessStreaming(exe, args, ...)` - Run process with streaming output
- `commandExists(command)` - Check if command is available in PATH

---

### `archive_manager.dart` - Archive Operations

Compression and extraction utilities.

**Functions:**
- `extractZip(zipPath, destDir)` - Extract ZIP archive
- `extractTarBz2(tarPath, destDir)` - Extract TAR.BZ2 archive
- `createTarBz2(sourceDir, archivePath)` - Create TAR.BZ2 archive
- `createTarGz(sourceDir, archivePath)` - Create TAR.GZ archive (fast compression)
- `extractTarGz(tarPath, destDir)` - Extract TAR.GZ archive
- `createZip(sourceDir, zipPath)` - Create ZIP archive

---

### `sdk_downloader.dart` - SDK Download (Consumer Mode)

Downloads pre-built SDK from GitHub Releases.

**Functions:**
- `downloadSDK(version)` - Download and install SDK from releases

---

### `utils.dart` - General Utilities

General utility functions.

**Functions:**
- `compareVersions(a, b)` - Compare semantic version strings

---

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AGUS_MAPS_BUILD_MODE` | Build mode: `consumer` or `contributor` | Auto-detect |
| `COMAPS_TAG` | CoMaps git tag to use | `v2026.01.08-11` |
| `ANDROID_HOME` | Android SDK path | Auto-detect |
| `ANDROID_SDK_ROOT` | Android SDK path (alternative) | Auto-detect |
| `ANDROID_NDK_HOME` | Android NDK path | Auto-detect |
| `ANDROID_NDK` | Android NDK path (alternative) | Auto-detect |
| `VCPKG_ROOT` | vcpkg installation path | `C:\vcpkg` (Windows) |
| `DEBUG` | Enable debug stack traces | `false` |

---

## Build Modes

### Consumer Mode

For users who want to use the plugin without building from source:

1. SDK is downloaded from GitHub Releases
2. Pre-built binaries are used
3. No source compilation required

Set with: `AGUS_MAPS_BUILD_MODE=consumer` or having `AGUS_MAPS_HOME` set.

### Contributor Mode

For developers contributing to the plugin:

1. CoMaps is cloned from source
2. Patches are applied
3. Native binaries are built locally
4. Full development workflow

Set with: `AGUS_MAPS_BUILD_MODE=contributor` or auto-detected when in plugin repository with `patches/comaps/` directory.

---

## Platform-Specific Notes

### Windows

- Requires Visual Studio 2019/2022 with "Desktop development with C++" workload
- CMake from Android SDK can be used if not in PATH
- vcpkg is used for dependencies (set `VCPKG_ROOT`)
- Git Bash is used for Unix-style scripts

### macOS

- Xcode Command Line Tools required
- CocoaPods for iOS/macOS builds
- Metal shaders compiled automatically
- Builds both arm64 and x86_64 architectures

### Linux

- Requires CMake, Ninja, and GCC
- Android NDK required for Android builds

### Android (Cross-Platform)

- Android NDK required (install via Android Studio SDK Manager)
- Builds arm64-v8a, armeabi-v7a, and x86_64 ABIs
- Minimum SDK: 24 (Android 7.0)

---

## Troubleshooting

### CMake not found

Install CMake or use the one bundled with Android SDK:
```powershell
# Windows: Install via Android Studio SDK Manager
# Or set PATH to include cmake from Android SDK
```

### Patch application fails

1. Ensure working tree is clean: `git status` in thirdparty/comaps
2. Reset and retry: `git reset --hard HEAD`
3. Check patch file format (LF line endings, UTF-8)

### Boost headers build fails

Windows: Ensure Visual Studio is installed with C++ workload, or run from Developer Command Prompt.

### Android NDK not found

Install via Android Studio SDK Manager, or set `ANDROID_NDK_HOME` environment variable.

### CocoaPods issues (macOS)

```bash
# Install CocoaPods
sudo gem install cocoapods

# Update repos
pod repo update
```

---

## License

This tooling is part of the Agus Maps Flutter plugin. See the main LICENSE file for details.
